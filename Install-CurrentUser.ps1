[CmdletBinding(SupportsShouldProcess)]
param([string]$Version = '')
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -lt 7){throw '需要 PowerShell 7。'}
$source=$PSScriptRoot
$toolkitMetadata=Get-Content -Raw -LiteralPath (Join-Path $source 'toolkit.json') | ConvertFrom-Json
if(-not $Version){$Version=[string]$toolkitMetadata.version}
$sourceCommit=''
$git=Get-Command git.exe -ErrorAction SilentlyContinue
if($git -and (Test-Path -LiteralPath (Join-Path $source '.git'))){$sourceCommit=(& $git.Source -C $source rev-parse HEAD).Trim()}
$documents=[Environment]::GetFolderPath('MyDocuments')
$target=Join-Path $documents "PowerShell\Modules\GameModdingToolkit\$Version"
if(Test-Path -LiteralPath $target){throw "目标版本已存在，拒绝覆盖：$target"}
if($PSCmdlet.ShouldProcess($target,'安装 GameModdingToolkit')){
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach($directory in 'capabilities','games','shared','docs'){Copy-Item -LiteralPath (Join-Path $source $directory) -Destination $target -Recurse}
    foreach($file in 'AGENTS.md','README.md','README.en.md','toolkit.json','New-ModProjectProfile.ps1','Test-ModdingToolkitEnvironment.ps1'){
        Copy-Item -LiteralPath (Join-Path $source $file) -Destination $target
    }
    @{Version=$Version;SourceRepository=[string]$toolkitMetadata.repository;SourceCommit=$sourceCommit;InstalledAt=(Get-Date).ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'installation.json') -Encoding utf8
    Write-Output $target
}
