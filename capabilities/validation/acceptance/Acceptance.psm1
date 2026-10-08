#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Assert-Schema($Value,[string]$Name){
    $json=$Value | ConvertTo-Json -Depth 30
    if(!($json | Test-Json -SchemaFile (Join-Path $PSScriptRoot "schemas/$Name.schema.json") -ErrorAction SilentlyContinue)){throw "无效的 $Name v1 配置"}
}
function Get-Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Resolve-Evidence([string]$Root,[string]$Relative){
    if([IO.Path]::IsPathRooted($Relative)){throw '证据必须使用相对路径'}
    $base=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $path=[IO.Path]::GetFullPath((Join-Path $base $Relative))
    if(!$path.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw '证据路径越界'}
    $cursor=$path
    while($cursor -ne $base){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '证据路径不能包含链接'}
        $cursor=Split-Path $cursor -Parent
    }
    if((Get-Item -LiteralPath $base -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '证据根目录不能是链接'}
    $path
}
function Test-LayoutGeometry {
    param([Parameter(Mandatory)][hashtable]$Layout)
    Assert-Schema $Layout 'layout'
    $issues=[Collections.Generic.List[object]]::new()
    $ids=[Collections.Generic.HashSet[string]]::new()
    foreach($e in $Layout.elements){
        if(!$ids.Add($e.id)){throw "重复元素编号: $($e.id)"}
        $r=$e.rect
        if($r.x -lt 0 -or $r.y -lt 0 -or $r.x+$r.width -gt $Layout.canvas.width -or $r.y+$r.height -gt $Layout.canvas.height){$issues.Add(@{type='out-of-bounds';elements=@($e.id)})}
        if($e.textBounds.width -gt $r.width -or $e.textBounds.height -gt $r.height){$issues.Add(@{type='text-clipping';elements=@($e.id)})}
    }
    for($i=0;$i -lt $Layout.elements.Count;$i++){
        for($j=$i+1;$j -lt $Layout.elements.Count;$j++){
            $a=$Layout.elements[$i];$b=$Layout.elements[$j];$ra=$a.rect;$rb=$b.rect
            if($ra.x -lt $rb.x+$rb.width -and $rb.x -lt $ra.x+$ra.width -and $ra.y -lt $rb.y+$rb.height -and $rb.y -lt $ra.y+$ra.height){
                if($a.kind -eq 'content' -and $b.kind -eq 'content'){$issues.Add(@{type='content-overlap';elements=@($a.id,$b.id)})}
                elseif($a.kind -ne $b.kind){
                    $popup=if($a.kind -eq 'popup'){$a}else{$b};$content=if($a.kind -eq 'content'){$a}else{$b}
                    if($popup.layer -le $content.layer){$issues.Add(@{type='popup-layer';elements=@($popup.id,$content.id)})}
                }
            }
        }
    }
    if(@($Layout.elements | Where-Object kind -eq 'popup').Count){
        foreach($e in $Layout.elements | Where-Object { $_.kind -eq 'content' -and $_.receivesInput }){$issues.Add(@{type='background-input';elements=@($e.id)})}
    }
    @{schemaVersion=1;passed=$issues.Count -eq 0;issues=$issues.ToArray()}
}
function Test-ArtifactAcceptance {
    param([Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][hashtable]$Acceptance,
          [Parameter(Mandatory)][string]$EvidenceRoot,[Parameter(Mandatory)][string]$SourceCommit,
          [Parameter(Mandatory)][hashtable]$Runtime,[string]$InstalledArtifact)
    Assert-Schema $Acceptance 'acceptance';Assert-Schema $Runtime 'runtime'
    $sha=Get-Sha $Artifact;$issues=[Collections.Generic.List[string]]::new()
    if($sha -ne $Acceptance.artifactSha256){$issues.Add('candidate-hash')}
    if($SourceCommit -ne $Acceptance.sourceCommit){$issues.Add('source-commit')}
    if(!$Runtime.loaded -or $Runtime.faulted -or $Runtime.artifactSha256 -ne $sha -or $Runtime.sourceCommit -ne $SourceCommit){$issues.Add('runtime-identity')}
    if($InstalledArtifact -and (Get-Sha $InstalledArtifact) -ne $sha){$issues.Add('installed-hash')}
    $ids=[Collections.Generic.HashSet[string]]::new()
    foreach($c in $Acceptance.checks){
        if(!$ids.Add($c.id)){throw "重复验收项: $($c.id)"}
        if(!$c.required){continue}
        if($c.status -ne 'passed' -or $c.artifactSha256 -ne $sha){$issues.Add("check:$($c.id)");continue}
        if(!$c.evidence.Count){$issues.Add("evidence-missing:$($c.id)")}
        foreach($e in $c.evidence){
            try{$path=Resolve-Evidence $EvidenceRoot $e.path;if((Get-Sha $path) -ne $e.sha256){$issues.Add("evidence-hash:$($c.id)")}}
            catch{$issues.Add("evidence-invalid:$($c.id):$($_.Exception.Message)")}
        }
    }
    if(!@($Acceptance.checks | Where-Object required).Count){$issues.Add('required-checks-missing')}
    @{schemaVersion=1;passed=$issues.Count -eq 0;artifactSha256=$sha;sourceCommit=$SourceCommit;issues=$issues.ToArray()}
}
function Invoke-ScenarioAcceptance {
    param([Parameter(Mandatory)][hashtable]$Profile,[Parameter(Mandatory)][string]$AdapterModule,
          [Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][string]$SourceCommit,
          [Parameter(Mandatory)][string]$OutputDirectory)
    Assert-Schema $Profile 'scenarios'
    if($SourceCommit -notmatch '^[0-9a-fA-F]{40}$'){throw 'SourceCommit 必须是完整提交 SHA'}
    if(Test-Path -LiteralPath $OutputDirectory){throw '证据输出目录已存在，拒绝覆盖'}
    $ids=[Collections.Generic.HashSet[string]]::new()
    foreach($s in $Profile.scenarios){if(!$ids.Add($s.id)){throw "重复场景: $($s.id)"}}
    $sha=Get-Sha $Artifact
    $adapter=Import-Module -Name ([IO.Path]::GetFullPath($AdapterModule)) -Force -PassThru
    foreach($name in 'Save-AcceptanceState','Enter-AcceptanceScenario','Get-AcceptanceObservation','Save-AcceptanceEvidence','Restore-AcceptanceState'){
        if(!$adapter.ExportedCommands.ContainsKey($name)){Remove-Module $adapter;throw "适配器缺少: $name"}
    }
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    $report=@{schemaVersion=1;artifactSha256=$sha;sourceCommit=$SourceCommit;runtimeId=$Profile.runtimeId;kind='automated';passed=$false;restored=$false;error='';scenarios=@()}
    $saved=$false
    try {
        $state=& $adapter.ExportedCommands['Save-AcceptanceState'];$saved=$true
        foreach($case in $Profile.scenarios){
            $item=@{id=$case.id;status='failed';artifactSha256=$sha;observation=@{};evidence=@();error=''}
            $report.scenarios+=,$item
            try {
                & $adapter.ExportedCommands['Enter-AcceptanceScenario'] -Scenario $case | Out-Null
                $clock=[Diagnostics.Stopwatch]::StartNew()
                do {
                    $observed=& $adapter.ExportedCommands['Get-AcceptanceObservation']
                    Assert-Schema $observed 'observation'
                    if($observed.runtimeId -ne $Profile.runtimeId -or $observed.artifactSha256 -ne $sha){throw '运行时或制品身份不符'}
                    if($observed.ready){break}
                    if($clock.Elapsed.TotalSeconds -ge $Profile.timeoutSeconds){throw '场景就绪超时'}
                    Start-Sleep -Milliseconds 50
                } while($true)
                $item.observation=$observed
                foreach($key in $case.expected.Keys){
                    if(!$observed.values.ContainsKey($key) -or ($observed.values[$key] | ConvertTo-Json -Compress) -cne ($case.expected[$key] | ConvertTo-Json -Compress)){throw "观察断言失败: $key"}
                }
                $dir=Join-Path $OutputDirectory $case.id;New-Item -ItemType Directory -Path $dir | Out-Null
                $paths=@(& $adapter.ExportedCommands['Save-AcceptanceEvidence'] -OutputDirectory $dir)
                if(!$paths.Count){throw '适配器没有返回证据'}
                foreach($path in $paths){
                    $relative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($OutputDirectory),[IO.Path]::GetFullPath($path))
                    $verified=Resolve-Evidence $OutputDirectory $relative
                    $item.evidence+=@{path=$relative;sha256=Get-Sha $verified}
                }
                $item.status='passed'
            } catch {$item.error=$_.Exception.Message;break}
        }
    } catch {$report.error=$_.Exception.Message}
    finally {
        if($saved){try{& $adapter.ExportedCommands['Restore-AcceptanceState'] -State $state | Out-Null;$report.restored=$true}catch{$report.error="恢复失败: $($_.Exception.Message)"}}
        Remove-Module $adapter
        $report.passed=$report.restored -and !$report.error -and $report.scenarios.Count -eq $Profile.scenarios.Count -and !@($report.scenarios | Where-Object status -ne 'passed').Count
        $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'report.json') -Encoding utf8NoBOM
    }
    $report
}
Export-ModuleMember -Function Test-LayoutGeometry,Test-ArtifactAcceptance,Invoke-ScenarioAcceptance
