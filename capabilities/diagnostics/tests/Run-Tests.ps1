#Requires -Version 7.0
param([Parameter(Mandatory)][string]$WorkDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Assert($value,$message){if(!$value){throw $message}}
$entry=Join-Path (Split-Path $PSScriptRoot -Parent) 'Collect-HunterBlueprintDiagnostic.ps1'
if(Test-Path -LiteralPath $WorkDirectory){throw '测试目录必须不存在'}
New-Item -ItemType Directory -Path $WorkDirectory | Out-Null
$game=Join-Path $WorkDirectory '中文 游戏'
New-Item -ItemType Directory -Path "$game/reframework/autorun/LoadoutClone" -Force | Out-Null
$lua='reframework/autorun/LoadoutClone.lua'
[IO.File]::WriteAllText((Join-Path $game $lua),'version one')
$hash=(Get-FileHash -LiteralPath (Join-Path $game $lua)).Hash
$manifest=@{name='Hunter Blueprint';version='1.1.0';commit=('a'*40);sha256=@{$lua=$hash}}
function MakeArchive($m,$name){
 $path=Join-Path $WorkDirectory "$name.zip"
 $z=[IO.Compression.ZipFile]::Open($path,'Create')
 try{$e=$z.CreateEntry('manifest.json');$w=[IO.StreamWriter]::new($e.Open());try{$w.Write(($m|ConvertTo-Json -Depth 8))}finally{$w.Dispose()}}finally{$z.Dispose()}
 return $path
}
$archive=MakeArchive $manifest 'release'
$script:count=0
function Collect($name){
 & $entry -GamePath $game -ReleaseArchive $archive -OutputDirectory (Join-Path $WorkDirectory $name) | Out-Null
 $script:count++
 return Get-Content -Raw -LiteralPath (Join-Path $WorkDirectory "$name/report.json") | ConvertFrom-Json
}
$before=(Get-FileHash -LiteralPath (Join-Path $game $lua)).Hash
$r=Collect 'normal'
Assert ($r.installation -eq 'matched' -and $r.runtime -eq 'unknown') '文件匹配不能宣称运行时通过'
Assert ($r.logs.status -eq 'missing') '缺日志必须明确'
Assert ($r.frameworkVersion -eq 'unknown') '未知框架不能猜测'
Assert ((Get-FileHash -LiteralPath (Join-Path $game $lua)).Hash -eq $before) '不得修改输入'
[IO.File]::WriteAllText((Join-Path $game $lua),'old version')
$r=Collect 'mixed'; Assert ($r.files[0].status -eq 'different' -and $r.installation -eq 'mismatch') '混装必须发现'
[IO.File]::Delete((Join-Path $game $lua))
$r=Collect 'missing'; Assert ($r.files[0].status -eq 'missing') '缺文件必须发现'
[IO.File]::WriteAllText((Join-Path $game $lua),'version one')
[IO.File]::WriteAllText("$game/reframework/autorun/LoadoutClone/obsolete.lua",'old')
$r=Collect 'extra'; Assert ($r.extraLuaCount -eq 1 -and $r.installation -eq 'mismatch') '残留模块必须发现'
[IO.File]::Delete("$game/reframework/autorun/LoadoutClone/obsolete.lua")
$log=Join-Path $game 're2_framework_log.txt'
[IO.File]::WriteAllText($log,"玩家=秘密名字 SteamID=76561198000000000 token=secret123 C:\Users\PrivateName\data`n[LoadoutClone] error: traceback test`n")
$r=Collect 'private'
$text=Get-Content -Raw -LiteralPath (Join-Path $WorkDirectory 'private/report.json')
Assert ($text -notmatch '秘密名字|76561198000000000|secret123|PrivateName') '敏感日志不得导出'
Assert ($r.logs.events.Count -gt 0) '应提取错误类别'
$stream=[IO.File]::Open($log,'Open','ReadWrite','ReadWrite')
try{$r=Collect 'shared';Assert ($r.logs.status -eq 'sampled') '共享写入日志应可采集'}finally{$stream.Dispose()}
$stream=[IO.File]::Open($log,'Open','ReadWrite','None')
try{$r=Collect 'locked';Assert ($r.logs.status -eq 'unreadable') '独占日志应明确不可读'}finally{$stream.Dispose()}
[IO.File]::WriteAllText($log,('x'*300000)+"`n[LoadoutClone] error`n")
$r=Collect 'bounded';Assert ($r.logs.truncated -and $r.logs.bytesRead -le 262144) '日志必须限制读取量'
$stream=[IO.File]::Open((Join-Path $game $lua),'Open','ReadWrite','None')
try{$r=Collect 'locked-lua';Assert ($r.files[0].status -eq 'unreadable' -and $r.installation -eq 'mismatch') '锁定安装文件不能报匹配'}finally{$stream.Dispose()}
function Reject($label,[scriptblock]$action){$failed=$false;try{& $action | Out-Null}catch{$failed=$true};Assert $failed "$label 应拒绝";$script:count++}
Reject '覆盖输出' {& $entry -GamePath $game -ReleaseArchive $archive -OutputDirectory (Join-Path $WorkDirectory 'normal')}
Reject '写入游戏' {& $entry -GamePath $game -ReleaseArchive $archive -OutputDirectory "$game/report"}
foreach($path in @('../escape.lua','C:/escape.lua','reframework/autorun/LoadoutClone/../escape.lua','reframework/autorun/LoadoutClone/bad:stream.lua')){
 $bad=@{name='Hunter Blueprint';version='1.1.0';commit=('a'*40);sha256=@{$path=$hash}}
 $a=MakeArchive $bad ('bad'+$count)
 Reject '非法清单路径' {& $entry -GamePath $game -ReleaseArchive $a -OutputDirectory (Join-Path $WorkDirectory ('rejected'+$count))}
}
$bad=@{name='Hunter Blueprint';version='1.1.0';commit=('a'*40);sha256=@{}}
$a=MakeArchive $bad 'empty';Reject '空清单' {& $entry -GamePath $game -ReleaseArchive $a -OutputDirectory (Join-Path $WorkDirectory 'empty-output')}
$bad.sha256=@{$lua='invalid'};$a=MakeArchive $bad 'hash';Reject '非法哈希' {& $entry -GamePath $game -ReleaseArchive $a -OutputDirectory (Join-Path $WorkDirectory 'hash-output')}
$outside=Join-Path $WorkDirectory 'outside';New-Item -ItemType Directory $outside | Out-Null
$link=Join-Path $WorkDirectory 'linked-game';New-Item -ItemType Junction -Path $link -Target $game | Out-Null
Reject 'junction 游戏' {& $entry -GamePath $link -ReleaseArchive $archive -OutputDirectory (Join-Path $WorkDirectory 'junction-output')}
$outputLink=Join-Path $WorkDirectory 'linked-output';New-Item -ItemType Junction -Path $outputLink -Target $game | Out-Null
Reject 'junction 输出' {& $entry -GamePath $game -ReleaseArchive $archive -OutputDirectory "$outputLink/new-report"}
$moduleLink=Join-Path $game 'reframework/fonts';New-Item -ItemType Junction -Path $moduleLink -Target $outside | Out-Null
$fontManifest=@{name='Hunter Blueprint';version='1.1.0';commit=('a'*40);sha256=@{$lua=$hash;'reframework/fonts/NotoSansSC-Regular.otf'=$hash}}
$a=MakeArchive $fontManifest 'linked-font'
Reject 'junction 内部负载' {& $entry -GamePath $game -ReleaseArchive $a -OutputDirectory (Join-Path $WorkDirectory 'linked-font-report')}
$zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $WorkDirectory 'private/diagnostic.zip'))
try{Assert ($zip.Entries.Count -eq 2) '包中仅有报告和说明'}finally{$zip.Dispose()}
Write-Output "DIAGNOSTIC_TESTS=PASS; scenarios=$count"
