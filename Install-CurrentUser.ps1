[CmdletBinding(SupportsShouldProcess)]
param([string]$Version = '0.1.0')
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -lt 7){throw '需要 PowerShell 7。'}
$source=$PSScriptRoot
$documents=[Environment]::GetFolderPath('MyDocuments')
$target=Join-Path $documents "PowerShell\Modules\GameModdingToolkit\$Version"
if(Test-Path -LiteralPath $target){throw "目标版本已存在，拒绝覆盖：$target"}
if($PSCmdlet.ShouldProcess($target,'安装 GameModdingToolkit')){
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'capabilities') -Destination $target -Recurse
    Copy-Item -LiteralPath (Join-Path $source 'games') -Destination $target -Recurse
    @{Version=$Version;SourceRepository='https://github.com/boyl/game-modding-toolkit';InstalledAt=(Get-Date).ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'installation.json') -Encoding utf8
    Write-Output $target
}
