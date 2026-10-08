#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Layout,[string]$ReportPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Acceptance.psm1') -Force
$result=Test-LayoutGeometry -Layout (Get-Content -LiteralPath $Layout -Raw | ConvertFrom-Json -AsHashtable)
$json=$result | ConvertTo-Json -Depth 12
if($ReportPath){if(Test-Path -LiteralPath $ReportPath){throw '报告已存在，拒绝覆盖'};$json | Set-Content -LiteralPath $ReportPath -Encoding utf8NoBOM}
$json
if(!$result.passed){throw '布局诊断失败，见 issues。'}
