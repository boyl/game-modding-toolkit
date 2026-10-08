#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][string]$Acceptance,[Parameter(Mandatory)][string]$EvidenceRoot,[Parameter(Mandatory)][string]$SourceCommit,[Parameter(Mandatory)][string]$RuntimeEvidence,[string]$InstalledArtifact,[string]$ReportPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Acceptance.psm1') -Force
$result=Test-ArtifactAcceptance -Artifact $Artifact -Acceptance (Get-Content -LiteralPath $Acceptance -Raw | ConvertFrom-Json -AsHashtable) -EvidenceRoot $EvidenceRoot -SourceCommit $SourceCommit -Runtime (Get-Content -LiteralPath $RuntimeEvidence -Raw | ConvertFrom-Json -AsHashtable) -InstalledArtifact $InstalledArtifact
$json=$result | ConvertTo-Json -Depth 12
if($ReportPath){if(Test-Path -LiteralPath $ReportPath){throw '报告已存在，拒绝覆盖'};$json | Set-Content -LiteralPath $ReportPath -Encoding utf8NoBOM}
$json
if(!$result.passed){throw '制品验收门禁失败，见 issues。'}
