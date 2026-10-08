#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Profile,[Parameter(Mandatory)][string]$AdapterModule,[Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][string]$SourceCommit,[Parameter(Mandatory)][string]$OutputDirectory,[switch]$Run)
$ErrorActionPreference='Stop'
if(!$Run){throw '场景执行会临时修改运行时设置，需要显式 -Run；纯诊断请使用其他两个工具。'}
Import-Module (Join-Path $PSScriptRoot 'Acceptance.psm1') -Force
$result=Invoke-ScenarioAcceptance -Profile (Get-Content -LiteralPath $Profile -Raw | ConvertFrom-Json -AsHashtable) -AdapterModule $AdapterModule -Artifact $Artifact -SourceCommit $SourceCommit -OutputDirectory $OutputDirectory
$result | ConvertTo-Json -Depth 30
if(!$result.passed){throw '场景验收失败，见输出目录的 report.json。'}
