[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectProfile,
    [string[]]$Variant,
    [uri]$Proxy,
    [switch]$Publish,
    [string]$ChangeNotesFile,
    [switch]$SkipVerify,
    [string]$UploaderPath,
    [ValidateRange(30, 300)][int]$UploadTimeoutSeconds,
    [Parameter(DontShow = $true)][string]$RemoteProviderPath,
    [Parameter(DontShow = $true)][string]$AdapterPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Invoke-WorkshopRelease.ps1 必须使用 PowerShell 7 或更高版本。'
}

$modulePath = Join-Path $PSScriptRoot 'src\WorkshopRelease.psm1'
Import-Module $modulePath -Force
Invoke-GMTWorkshopRelease @PSBoundParameters
