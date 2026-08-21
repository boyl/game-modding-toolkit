[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('the-binding-of-isaac')][string]$Game,
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][hashtable[]]$Variant,
    [string]$ProjectName,
    [hashtable[]]$Hook = @(),
    [string]$EvidenceDirectory = 'artifacts/workshop-release',
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'New-ModProjectProfile.ps1 需要 PowerShell 7。' }

$module = Join-Path $PSScriptRoot 'shared\powershell\ProjectProfile.psm1'
Import-Module $module -Force
$target = [IO.Path]::GetFullPath($OutputPath)
if ((Test-Path -LiteralPath $target) -and -not $Force) { throw "目标配置已存在，拒绝覆盖：$target" }
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $trimmed = $ProjectRoot.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $ProjectName = [IO.Path]::GetFileName($trimmed)
}
if ([string]::IsNullOrWhiteSpace($ProjectName)) { throw '无法推导项目名称，请显式提供 -ProjectName。' }

$variants = foreach ($item in $Variant) {
    [ordered]@{
        name = [string]$item.name
        publishedFileId = [string]$item.publishedFileId
        expectedTitle = [string]$item.expectedTitle
        descriptionMarker = [string]$item.descriptionMarker
        candidateDirectory = [string]$item.candidateDirectory
        metadataFile = if ($item.ContainsKey('metadataFile')) { [string]$item.metadataFile } else { 'metadata.xml' }
        previewFile = if ($item.ContainsKey('previewFile')) { [string]$item.previewFile } else { 'preview.png' }
    }
}
$hooks = foreach ($item in $Hook) {
    $value = [ordered]@{ phase=[string]$item.phase; executable=[string]$item.executable; arguments=@($item.arguments | ForEach-Object { [string]$_ }) }
    if ($item.ContainsKey('variant')) { $value['variant']=[string]$item.variant }
    $value
}
$profile = [ordered]@{
    schemaVersion = 1
    projectName = $ProjectName
    projectRoot = $ProjectRoot
    evidenceDirectory = $EvidenceDirectory
    adapter = [ordered]@{ id='isaac-mod-uploader'; configuration=[ordered]@{ mainWindowTitle='The Binding of Isaac: Afterbirth+ Mod Uploader'; uploadTimeoutSeconds=150 } }
    policies = [ordered]@{ requireCleanPushedHead=$true; preserveRemotePreview=$true }
    hooks = @($hooks)
    variants = @($variants)
}
$json = $profile | ConvertTo-Json -Depth 16
$schema = Get-GMTProjectProfileSchemaPath
if (-not ($json | Test-Json -SchemaFile $schema -ErrorAction Stop)) { throw '生成的项目配置未通过 Schema 验证。' }

if ($PSCmdlet.ShouldProcess($target,'创建 Mod 项目发布配置')) {
    $parent = Split-Path $target -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json | Set-Content -LiteralPath $target -Encoding UTF8
    Read-GMTValidatedProjectProfile -Path $target | Out-Null
    Write-Output $target
    Write-Output 'GAME_MODDING_TOOLKIT_PROFILE=OK'
}
