[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectProfile,
    [string]$ToolkitLock,
    [string]$UploaderPath,
    [uri]$Proxy,
    [switch]$Online,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Test-ModdingToolkitEnvironment.ps1 需要 PowerShell 7。' }

$toolkitRoot = $PSScriptRoot
$toolkitMetadata = Get-Content -Raw -LiteralPath (Join-Path $toolkitRoot 'toolkit.json') -Encoding UTF8 | ConvertFrom-Json
$profileModule = Join-Path $toolkitRoot 'shared\powershell\ProjectProfile.psm1'
Import-Module $profileModule -Force
$checks = [Collections.Generic.List[object]]::new()
function Add-Check([string]$Name,[bool]$Passed,[string]$Detail) {
    $checks.Add([ordered]@{ name=$Name; passed=$Passed; detail=$Detail })
}
function Resolve-ProjectPath([string]$Base,[string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $Base $Path))
}

Add-Check 'powershell' $true $PSVersionTable.PSVersion.ToString()
Add-Check 'platform' $IsWindows 'Windows'
$profileInfo = Read-GMTValidatedProjectProfile -Path $ProjectProfile
Add-Check 'profile-schema' $true $profileInfo.Path
$profile = $profileInfo.Value
$projectRoot = Resolve-ProjectPath $profileInfo.Directory ([string]$profile.projectRoot)
Add-Check 'project-root' (Test-Path -LiteralPath $projectRoot -PathType Container) $projectRoot

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
Add-Check 'git' ($null -ne $gitCommand) $(if($gitCommand){$gitCommand.Source}else{'未找到 git.exe'})
$requiresGit = -not ($profile.PSObject.Properties['policies'] -and $profile.policies.PSObject.Properties['requireCleanPushedHead'] -and -not [bool]$profile.policies.requireCleanPushedHead)
if ($gitCommand -and (Test-Path -LiteralPath $projectRoot -PathType Container) -and $requiresGit) {
    $inside = (& $gitCommand.Source -C $projectRoot rev-parse --is-inside-work-tree 2>$null) -eq 'true'
    Add-Check 'git-repository' $inside $projectRoot
    if ($inside) {
        $status = @(& $gitCommand.Source -C $projectRoot status --porcelain)
        Add-Check 'git-clean' ($status.Count -eq 0) $(if($status){$status -join '; '}else{'工作树干净'})
        if ($Online) {
            $branch = (& $gitCommand.Source -C $projectRoot branch --show-current).Trim()
            $head = (& $gitCommand.Source -C $projectRoot rev-parse HEAD).Trim()
            $gitArgs = @('-C',$projectRoot)
            if ($Proxy) { $gitArgs += @('-c',"http.proxy=$Proxy") }
            $remoteLine = & $gitCommand.Source @gitArgs ls-remote origin "refs/heads/$branch" 2>$null | Select-Object -First 1
            $remoteHead = if($remoteLine){($remoteLine -split "`t")[0]}else{''}
            Add-Check 'git-pushed' ($head -eq $remoteHead) "local=$head remote=$remoteHead"
        }
    }
}

if ($ToolkitLock) {
    $lockPath = (Resolve-Path -LiteralPath $ToolkitLock -ErrorAction Stop).Path
    $lock = Get-Content -Raw -LiteralPath $lockPath -Encoding UTF8 | ConvertFrom-Json
    Add-Check 'toolkit-repository' ([string]$toolkitMetadata.repository -eq [string]$lock.repository) "actual=$($toolkitMetadata.repository) expected=$($lock.repository)"
    $versionOk = [version]$toolkitMetadata.version -ge [version]$lock.minimumVersion
    Add-Check 'toolkit-version' $versionOk "installed=$($toolkitMetadata.version) minimum=$($lock.minimumVersion)"
    $sourceCommit = ''
    $installRecord = Join-Path $toolkitRoot 'installation.json'
    if (Test-Path -LiteralPath $installRecord) { $sourceCommit=[string]((Get-Content -Raw -LiteralPath $installRecord | ConvertFrom-Json).SourceCommit) }
    elseif ($gitCommand -and (Test-Path -LiteralPath (Join-Path $toolkitRoot '.git'))) { $sourceCommit=(& $gitCommand.Source -C $toolkitRoot rev-parse HEAD).Trim() }
    Add-Check 'toolkit-lock' ($sourceCommit -eq [string]$lock.verifiedCommit) "actual=$sourceCommit expected=$($lock.verifiedCommit)"
}

$profileHooks = if($profile.PSObject.Properties['hooks']){@($profile.hooks)}else{@()}
foreach ($hook in $profileHooks) {
    $command = Get-Command ([string]$hook.executable) -ErrorAction SilentlyContinue
    Add-Check "hook-$($hook.phase)-$($hook.executable)" ($null -ne $command) $(if($command){$command.Source}else{'找不到可执行文件'})
}
foreach ($variant in @($profile.variants)) {
    $candidate = Resolve-ProjectPath $projectRoot ([string]$variant.candidateDirectory)
    $metadataName = if($variant.PSObject.Properties['metadataFile']){[string]$variant.metadataFile}else{'metadata.xml'}
    $previewName = if($variant.PSObject.Properties['previewFile']){[string]$variant.previewFile}else{'preview.png'}
    $metadataPath = Join-Path $candidate $metadataName; $previewPath = Join-Path $candidate $previewName
    $filesOk = (Test-Path -LiteralPath $metadataPath -PathType Leaf) -and (Test-Path -LiteralPath $previewPath -PathType Leaf)
    Add-Check "candidate-$($variant.name)" $filesOk $candidate
    if ($filesOk) {
        [xml]$metadata = Get-Content -Raw -LiteralPath $metadataPath
        Add-Check "identity-$($variant.name)" ([string]$metadata.metadata.id -eq [string]$variant.publishedFileId) "expected=$($variant.publishedFileId) actual=$($metadata.metadata.id)"
    }
}

if ([string]$profile.adapter.id -ne 'isaac-mod-uploader') { throw "诊断器暂不支持适配器：$($profile.adapter.id)" }
$adapterPath = Join-Path $toolkitRoot 'games\the-binding-of-isaac\adapters\mod-uploader\IsaacModUploaderAdapter.psm1'
Import-Module $adapterPath -Force
$configuration = if($profile.adapter.PSObject.Properties['configuration']){$profile.adapter.configuration}else{[pscustomobject]@{}}
if($UploaderPath){$configuration | Add-Member -NotePropertyName uploaderPath -NotePropertyValue $UploaderPath -Force}
try {
    $adapterFacts = Test-GMTWorkshopAdapterEnvironment -Configuration $configuration
    Add-Check 'adapter-environment' $true ($adapterFacts | ConvertTo-Json -Compress)
} catch {
    Add-Check 'adapter-environment' $false $_.Exception.Message
}

if ($Online) {
    Import-Module (Join-Path $toolkitRoot 'capabilities\publishing\steam-workshop\src\SteamRemoteProvider.psm1') -Force
    foreach ($variant in @($profile.variants)) {
        $remote = Get-GMTRemoteWorkshopItem -PublishedFileId ([string]$variant.publishedFileId) -Proxy $Proxy
        Add-Check "remote-$($variant.name)" ($remote.title -eq [string]$variant.expectedTitle) "expected=$($variant.expectedTitle) actual=$($remote.title)"
    }
}

$failed = @($checks | Where-Object { -not $_.passed })
$result = [ordered]@{ schemaVersion=1; toolkitVersion=[string]$toolkitMetadata.version; online=[bool]$Online; passed=($failed.Count -eq 0); successMarker=$(if($failed.Count -eq 0){'GAME_MODDING_TOOLKIT_DOCTOR=OK'}else{$null}); checks=$checks }
if ($Json) { $result | ConvertTo-Json -Depth 8 } else { foreach($check in $checks){ Write-Host ('[{0}] {1}: {2}' -f $(if($check.passed){'OK'}else{'FAIL'}),$check.name,$check.detail) } }
if ($failed.Count -gt 0) { throw "环境诊断失败：$($failed.name -join ', ')" }
if(-not $Json){Write-Output 'GAME_MODDING_TOOLKIT_DOCTOR=OK'}
