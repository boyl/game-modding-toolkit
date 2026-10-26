#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Resolve-DiagnosticPath([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    $cursor=$full
    while($cursor){
        if(Test-Path -LiteralPath $cursor){
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '诊断路径不得包含重解析点。'}
        }
        $parent=[IO.Path]::GetDirectoryName($cursor)
        if($parent -eq $cursor){break}
        $cursor=$parent
    }
    return $full
}

function Read-HunterManifest([string]$Archive) {
    $path=Resolve-DiagnosticPath $Archive
    $zip=[IO.Compression.ZipFile]::OpenRead($path)
    try {
        $entries=@($zip.Entries | Where-Object FullName -CEQ 'manifest.json')
        if($entries.Count -ne 1 -or $entries[0].Length -gt 1048576){throw '发布包应包含唯一且小于 1 MiB 的 manifest.json。'}
        $reader=[IO.StreamReader]::new($entries[0].Open())
        try{$m=$reader.ReadToEnd() | ConvertFrom-Json -AsHashtable}finally{$reader.Dispose()}
    } finally {$zip.Dispose()}
    if($m -isnot [System.Collections.IDictionary] -or $m.name -cne 'Hunter Blueprint' -or
       $m.version -notmatch '^\d+\.\d+\.\d+$' -or $m.commit -notmatch '^[0-9a-fA-F]{40}$' -or
       $m.sha256 -isnot [System.Collections.IDictionary] -or $m.sha256.Count -lt 1 -or $m.sha256.Count -gt 256){throw '发布清单结构或版本字段无效。'}
    $files=[ordered]@{}
    foreach($key in $m.sha256.Keys){
        if($key -notmatch '^[a-zA-Z0-9_.\-/]+$' -or $key -match '(^/|(^|/)\.\.?(/|$))' -or $m.sha256[$key] -notmatch '^[0-9a-fA-F]{64}$'){throw '发布清单包含非法路径或哈希。'}
        if($key -ceq 'reframework/autorun/LoadoutClone.lua' -or
           $key -cmatch '^reframework/autorun/LoadoutClone/[A-Za-z0-9_]+\.lua$' -or
           $key -ceq 'reframework/fonts/NotoSansSC-Regular.otf'){
            $files[$key]=$m.sha256[$key].ToLowerInvariant()
        } elseif($key -cnotin @('README.md','licenses/NotoSansSC-OFL.txt','licenses/THIRD-PARTY-NOTICES.txt')) {throw '发布清单包含不受支持的负载路径。'}
    }
    if(!$files.Contains('reframework/autorun/LoadoutClone.lua')){throw '发布清单缺少猎人蓝图入口。'}
    return @{schemaVersion=1;name='Hunter Blueprint';version=$m.version;commit=$m.commit.ToLowerInvariant();files=$files}
}

function Read-DiagnosticLog([string]$Path) {
    $result=[ordered]@{status='missing';bytesRead=0;truncated=$false;events=@();scope='仅末尾采样及固定类别；无匹配不代表没有错误；不含原文。'}
    $safe=Resolve-DiagnosticPath $Path
    if(!(Test-Path -LiteralPath $safe -PathType Leaf)){return $result}
    $stream=$null
    try {
        $stream=[IO.FileStream]::new($safe,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $length=$stream.Length
        $start=[Math]::Max(0,$length-262144)
        [void]$stream.Seek($start,[IO.SeekOrigin]::Begin)
        $buffer=[byte[]]::new([int]($length-$start));$read=0
        while($read -lt $buffer.Length){$n=$stream.Read($buffer,$read,$buffer.Length-$read);if($n -eq 0){break};$read+=$n}
        $text=[Text.Encoding]::UTF8.GetString($buffer,0,$read)
        if($start -gt 0){$newline=$text.IndexOf("`n");$text=if($newline -ge 0){$text.Substring($newline+1)}else{''}}
        $result.status='sampled';$result.bytesRead=$read;$result.truncated=$start -gt 0
        $events=[Collections.Generic.List[object]]::new();$index=0
        foreach($line in ($text -split "`n")){
            $index++
            # 只输出固定标签，绝不把任意日志内容、路径、玩家名称写入报告。
            if($line -match '(?i)LoadoutClone' -and $line -match '(?i)error|exception|failed|traceback'){
                $category=if($line -match '(?i)module.+not found'){'module-not-found'}elseif($line -match '(?i)traceback|debug'){'lua-error-context'}else{'mod-error'}
                $events.Add(@{sampleLine=$index;category=$category})
            }
            if($events.Count -eq 100){break}
        }
        $result.events=@($events.ToArray())
    } catch [IO.IOException] {$result.status='unreadable'}
      catch [UnauthorizedAccessException] {$result.status='unreadable'}
    finally {if($null -ne $stream){$stream.Dispose()}}
    return $result
}

function New-HunterDiagnosticReport([string]$GamePath,[hashtable]$Manifest) {
    $root=Resolve-DiagnosticPath $GamePath
    if(!(Test-Path -LiteralPath $root -PathType Container)){throw '游戏目录不存在。'}
    $rows=[Collections.Generic.List[object]]::new()
    foreach($relative in ($Manifest.files.Keys | Sort-Object)){
        $p=Resolve-DiagnosticPath (Join-Path $root $relative)
        $row=[ordered]@{path=$relative;expectedSha256=$Manifest.files[$relative];actualSha256=$null;status='missing'}
        if(Test-Path -LiteralPath $p -PathType Leaf){
            try{$row.actualSha256=(Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant();$row.status=if($row.actualSha256 -eq $row.expectedSha256){'matched'}else{'different'}}
            catch [IO.IOException] {$row.status='unreadable'}
            catch [UnauthorizedAccessException] {$row.status='unreadable'}
        }
        $rows.Add($row)
    }
    $modules=Resolve-DiagnosticPath (Join-Path $root 'reframework/autorun/LoadoutClone')
    $extras=0
    if(Test-Path -LiteralPath $modules -PathType Container){
        foreach($file in Get-ChildItem -LiteralPath $modules -File -Filter '*.lua'){
            [void](Resolve-DiagnosticPath $file.FullName)
            if(!$Manifest.files.Contains(('reframework/autorun/LoadoutClone/'+$file.Name))){$extras++}
        }
    }
    $exe=Resolve-DiagnosticPath (Join-Path $root 'MonsterHunterRise.exe')
    $gameVersion='unknown'
    if(Test-Path -LiteralPath $exe -PathType Leaf){
        $v=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion
        if($v -match '^\d+(\.\d+){1,3}$'){$gameVersion=$v}
    }
    $bad=@($rows | Where-Object status -NE 'matched').Count
    $logs=Read-DiagnosticLog (Join-Path $root 're2_framework_log.txt')
    return [ordered]@{
        schemaVersion=1;kind='passive-installation-diagnostic';expectedVersion=$Manifest.version;sourceCommit=$Manifest.commit
        installation=$(if($bad -eq 0 -and $extras -eq 0){'matched'}else{'mismatch'})
        runtime='unknown';gameVersion=$gameVersion;frameworkVersion='unknown'
        gameExecutablePresent=(Test-Path -LiteralPath $exe -PathType Leaf)
        files=@($rows.ToArray());extraLuaCount=$extras;logs=$logs
        limitations=@('文件匹配仅证明与所选本地发布清单一致，不认证发行包来源。','未检查游戏进程、存档、装备、其他 Mod 或框架实际加载版本。','错误事件只覆盖固定类别，原始日志未导出；不包含完整堆栈。')
    }
}
Export-ModuleMember -Function Resolve-DiagnosticPath,Read-HunterManifest,New-HunterDiagnosticReport
