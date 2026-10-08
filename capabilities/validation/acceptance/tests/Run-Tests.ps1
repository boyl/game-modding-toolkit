#Requires -Version 7.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'Acceptance.psm1') -Force
function Assert($condition,$message){if(!$condition){throw $message}}
$work=Join-Path ([IO.Path]::GetTempPath()) ('acceptance-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
$artifact=Join-Path $work 'candidate.bin';[IO.File]::WriteAllText($artifact,'candidate')
$sha=(Get-FileHash $artifact).Hash;$commit='a'*40
$layout=@{schemaVersion=1;canvas=@{width=100;height=100};elements=@(@{id='text';kind='content';layer=0;receivesInput=$false;rect=@{x=0;y=0;width=50;height=20};textBounds=@{width=49;height=18}})}
Assert (Test-LayoutGeometry $layout).passed 'L01有效几何应通过'
$layout.elements[0].textBounds.width=51;Assert (!(Test-LayoutGeometry $layout).passed) 'L01裁切必须失败'
$layout.elements[0].textBounds.width=49;$layout.elements[0].rect.x=80;Assert (!(Test-LayoutGeometry $layout).passed) 'L01越界必须失败';$layout.elements[0].rect.x=0
$layout.elements+=@{id='popup';kind='popup';layer=1;receivesInput=$true;rect=@{x=0;y=0;width=50;height=20};textBounds=@{width=40;height=18}}
Assert (Test-LayoutGeometry $layout).passed 'L03正确弹出层应允许覆盖'
$layout.elements[1].layer=-1;Assert (!(Test-LayoutGeometry $layout).passed) 'L03错误弹出层必须失败';$layout.elements[1].layer=1
$layout.elements[0].receivesInput=$true;Assert (!(Test-LayoutGeometry $layout).passed) 'L04背景输入冲突必须失败';$layout.elements[0].receivesInput=$false
$layout.elements[1].kind='content';Assert (!(Test-LayoutGeometry $layout).passed) 'L02普通内容重叠必须失败'
$evidence=Join-Path $work 'evidence.txt';[IO.File]::WriteAllText($evidence,'observed')
$accept=@{schemaVersion=1;artifactSha256=$sha;sourceCommit=$commit;checks=@(@{id='runtime';required=$true;status='passed';kind='runtime';artifactSha256=$sha;evidence=@(@{path='evidence.txt';sha256=(Get-FileHash $evidence).Hash})})}
$runtime=@{schemaVersion=1;loaded=$true;faulted=$false;artifactSha256=$sha;sourceCommit=$commit}
Assert (Test-ArtifactAcceptance -Artifact $artifact -Acceptance $accept -EvidenceRoot $work -SourceCommit $commit -Runtime $runtime -InstalledArtifact $artifact).passed 'G01一致证据应通过'
$accept.checks[0].artifactSha256='0'*64;Assert (!(Test-ArtifactAcceptance -Artifact $artifact -Acceptance $accept -EvidenceRoot $work -SourceCommit $commit -Runtime $runtime).passed) 'G02旧passed必须拒绝';$accept.checks[0].artifactSha256=$sha
foreach($status in 'failed','unverified'){ $accept.checks[0].status=$status;Assert (!(Test-ArtifactAcceptance -Artifact $artifact -Acceptance $accept -EvidenceRoot $work -SourceCommit $commit -Runtime $runtime).passed) 'G03必需项状态必须拒绝' };$accept.checks[0].status='passed'
[IO.File]::WriteAllText($evidence,'changed');Assert (!(Test-ArtifactAcceptance -Artifact $artifact -Acceptance $accept -EvidenceRoot $work -SourceCommit $commit -Runtime $runtime).passed) 'G03变更证据必须拒绝';[IO.File]::WriteAllText($evidence,'observed')
$runtime.sourceCommit='b'*40;Assert (!(Test-ArtifactAcceptance -Artifact $artifact -Acceptance $accept -EvidenceRoot $work -SourceCommit $commit -Runtime $runtime).passed) 'G04错误来源必须拒绝';$runtime.sourceCommit=$commit
[IO.File]::WriteAllText($artifact,'changed');Assert (!(Test-ArtifactAcceptance -Artifact $artifact -Acceptance $accept -EvidenceRoot $work -SourceCommit $commit -Runtime $runtime).passed) 'G02候选改变必须拒绝';[IO.File]::WriteAllText($artifact,'candidate')
$installed=Join-Path $work 'installed.bin';[IO.File]::WriteAllText($installed,'old');Assert (!(Test-ArtifactAcceptance -Artifact $artifact -Acceptance $accept -EvidenceRoot $work -SourceCommit $commit -Runtime $runtime -InstalledArtifact $installed).passed) 'G01错误安装副本必须拒绝'
$accept.checks[0].evidence[0].path='missing.txt';Assert (!(Test-ArtifactAcceptance -Artifact $artifact -Acceptance $accept -EvidenceRoot $work -SourceCommit $commit -Runtime $runtime).passed) 'G03缺失证据必须拒绝';$accept.checks[0].evidence[0].path='evidence.txt'
$adapter=Join-Path $work 'Adapter.psm1'
@'
$script:scenario=$null
function Save-AcceptanceState { return @{saved=$true} }
function Enter-AcceptanceScenario($Scenario){$script:scenario=$Scenario;if($Scenario.id -eq 'exception'){throw 'injected'}}
function Get-AcceptanceObservation {return @{ready=$script:scenario.id -ne 'timeout';runtimeId='test-runtime';artifactSha256=$script:scenario.sha;values=@{page=1}}}
function Save-AcceptanceEvidence($OutputDirectory){$p=Join-Path $OutputDirectory 'state.txt';[IO.File]::WriteAllText($p,'observed');return @($p)}
function Restore-AcceptanceState($State){if($script:scenario.id -eq 'restore-failure'){throw 'restore injected'};[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'restored.txt'),'restored')}
Export-ModuleMember -Function *-Acceptance*
'@ | Set-Content -LiteralPath $adapter -Encoding utf8NoBOM
$profile=@{schemaVersion=1;runtimeId='test-runtime';timeoutSeconds=0.1;scenarios=@(@{id='one';sha=$sha;expected=@{page=1}},@{id='two';sha=$sha;expected=@{page=1}})}
$r=Invoke-ScenarioAcceptance -Profile $profile -AdapterModule $adapter -Artifact $artifact -SourceCommit $commit -OutputDirectory (Join-Path $work 'good')
Assert ($r.passed -and $r.restored -and $r.scenarios.Count -eq 2) 'A01场景应通过并恢复'
foreach($id in 'timeout','exception','restore-failure'){$profile.scenarios=@(@{id=$id;sha=$sha;expected=@{page=1}});$r=Invoke-ScenarioAcceptance -Profile $profile -AdapterModule $adapter -Artifact $artifact -SourceCommit $commit -OutputDirectory (Join-Path $work $id);Assert (!$r.passed) "A02/A04失败不得放行:$id";if($id -ne 'restore-failure'){Assert $r.restored '失败也须恢复'}}
$profile.scenarios=@(@{id='wrong';sha='0'*64;expected=@{page=1}});$r=Invoke-ScenarioAcceptance -Profile $profile -AdapterModule $adapter -Artifact $artifact -SourceCommit $commit -OutputDirectory (Join-Path $work 'wrong');Assert (!$r.passed) 'A03错误制品必须拒绝'
$profile.scenarios=@(@{id='state';sha=$sha;expected=@{page=2}});$r=Invoke-ScenarioAcceptance -Profile $profile -AdapterModule $adapter -Artifact $artifact -SourceCommit $commit -OutputDirectory (Join-Path $work 'state');Assert (!$r.passed) 'A02观察结果不符必须拒绝'
$profile.runtimeId='another';$r=Invoke-ScenarioAcceptance -Profile $profile -AdapterModule $adapter -Artifact $artifact -SourceCommit $commit -OutputDirectory (Join-Path $work 'identity');Assert (!$r.passed) 'A03运行时身份不符必须拒绝'
Write-Output "ACCEPTANCE_TESTS=OK; evidence=$work"

