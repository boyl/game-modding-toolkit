Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-GMTCheckpoint {
    param([string]$Name, [string]$Detail = '')
    $suffix = if ($Detail) { " | $Detail" } else { '' }
    Write-Host ('[{0:HH:mm:ss}] {1}{2}' -f (Get-Date), $Name, $suffix)
}

function Resolve-GMTPath {
    param([string]$Base, [string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $Base $Path))
}

function Read-GMTProfile {
    param([string]$ProfilePath)
    $resolved = (Resolve-Path -LiteralPath $ProfilePath -ErrorAction Stop).Path
    $profile = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json -Depth 32
    if ($profile.schemaVersion -ne 1) { throw "不支持的项目配置版本：$($profile.schemaVersion)" }
    foreach ($required in 'projectName','projectRoot','adapter','variants') {
        if ($null -eq $profile.$required) { throw "项目配置缺少字段：$required" }
    }
    if (-not $profile.adapter.id -or $profile.variants.Count -lt 1) { throw '项目配置缺少适配器或变体。' }
    $names = @{}
    foreach ($item in $profile.variants) {
        foreach ($required in 'name','publishedFileId','expectedTitle','descriptionMarker','candidateDirectory') {
            if ([string]::IsNullOrWhiteSpace([string]$item.$required)) { throw "变体缺少字段 $required。" }
        }
        if ($names.ContainsKey($item.name)) { throw "变体名称重复：$($item.name)" }
        $names[$item.name] = $true
    }
    return [ordered]@{ Path=$resolved; Directory=Split-Path $resolved -Parent; Value=$profile }
}

function Invoke-GMTGit {
    param([string]$RepositoryRoot, [string[]]$Arguments)
    $git = (Get-Command git.exe -ErrorAction Stop).Source
    $output = & $git -C $RepositoryRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Git 命令失败：git $($Arguments -join ' ')`n$($output -join "`n")" }
    return $output
}

function Get-GMTGitFacts {
    param([string]$RepositoryRoot, [uri]$Proxy, [bool]$Required)
    if (-not $Required) { return [ordered]@{ Required=$false } }
    $status = Invoke-GMTGit $RepositoryRoot @('status','--porcelain')
    if ($status) { throw "Git 工作树不干净，拒绝发布：`n$($status -join "`n")" }
    $head = (Invoke-GMTGit $RepositoryRoot @('rev-parse','HEAD') | Select-Object -First 1).Trim()
    $branch = (Invoke-GMTGit $RepositoryRoot @('branch','--show-current') | Select-Object -First 1).Trim()
    if (-not $branch) { throw '当前处于 detached HEAD，拒绝发布。' }
    $args = @('ls-remote','origin',"refs/heads/$branch")
    if ($Proxy) {
        $args = @('-c',"http.proxy=$Proxy",'-c','http.sslBackend=openssl','-c','http.sslCAInfo=C:/Program Files/Git/mingw64/etc/ssl/certs/ca-bundle.crt') + $args
    }
    $line = Invoke-GMTGit $RepositoryRoot $args | Select-Object -First 1
    $remote = if ($line) { ($line -split "`t")[0] } else { '' }
    if ($head -ne $remote) { throw "本地 HEAD 尚未与 origin/$branch 同步：local=$head remote=$remote" }
    return [ordered]@{ Required=$true; Head=$head; Branch=$branch; RemoteHead=$remote }
}

function Invoke-GMTHook {
    param($Hook, [string]$RepositoryRoot)
    $command = Get-Command ([string]$Hook.executable) -ErrorAction Stop
    $arguments = @($Hook.arguments | ForEach-Object { [string]$_ })
    & $command.Source @arguments
    if ($LASTEXITCODE -ne 0) { throw "发布钩子失败：$($Hook.executable) $($arguments -join ' ')" }
}

function Get-GMTVariantFacts {
    param($Variant, [string]$RepositoryRoot)
    $candidate = Resolve-GMTPath $RepositoryRoot ([string]$Variant.candidateDirectory)
    $metadataName = if ($Variant.PSObject.Properties['metadataFile']) { [string]$Variant.metadataFile } else { 'metadata.xml' }
    $previewName = if ($Variant.PSObject.Properties['previewFile']) { [string]$Variant.previewFile } else { 'preview.png' }
    $metadataPath = Resolve-GMTPath $candidate $metadataName
    $previewPath = Resolve-GMTPath $candidate $previewName
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { throw "缺少候选 metadata：$metadataPath" }
    if (-not (Test-Path -LiteralPath $previewPath -PathType Leaf)) { throw "缺少候选预览图：$previewPath" }
    [xml]$metadata = Get-Content -Raw -LiteralPath $metadataPath
    $actualId = [string]$metadata.metadata.id
    if ($actualId -ne [string]$Variant.publishedFileId) {
        throw "Workshop ID 不匹配：expected=$($Variant.publishedFileId) actual=$actualId"
    }
    return [ordered]@{
        CandidateRoot=$candidate; MetadataPath=$metadataPath; PreviewPath=$previewPath
        Name=[string]$metadata.metadata.name; Version=[string]$metadata.metadata.version
        PreviewSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $previewPath).Hash
    }
}

function Resolve-GMTAdapterPath {
    param([string]$AdapterId, [string]$ExplicitPath)
    if ($ExplicitPath) { return (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path }
    $toolkitRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
    $known = Join-Path $toolkitRoot "games\the-binding-of-isaac\adapters\mod-uploader\IsaacModUploaderAdapter.psm1"
    if ($AdapterId -eq 'isaac-mod-uploader' -and (Test-Path -LiteralPath $known)) { return $known }
    throw "找不到发布适配器：$AdapterId"
}

function Invoke-GMTWorkshopRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectProfile, [string[]]$Variant, [uri]$Proxy,
        [switch]$Publish, [string]$ChangeNotesFile, [switch]$SkipVerify,
        [string]$UploaderPath, [string]$RemoteProviderPath, [string]$AdapterPath
    )
    $profileInfo = Read-GMTProfile $ProjectProfile
    $profile = $profileInfo.Value
    $projectRoot = Resolve-GMTPath $profileInfo.Directory ([string]$profile.projectRoot)
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) { throw "项目根目录不存在：$projectRoot" }
    $selected = if ($Variant) { @($profile.variants | Where-Object { $Variant -contains $_.name }) } else { @($profile.variants) }
    if ($selected.Count -ne ($(if($Variant){$Variant.Count}else{$profile.variants.Count}))) { throw '请求的变体不存在或重复。' }
    $evidenceRelative = if ($profile.PSObject.Properties['evidenceDirectory']) { [string]$profile.evidenceDirectory } else { 'artifacts/workshop-release' }
    $evidenceRoot = Join-Path (Resolve-GMTPath $projectRoot $evidenceRelative) (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
    $requiredGit = $true
    if ($profile.PSObject.Properties['policies'] -and $profile.policies.PSObject.Properties['requireCleanPushedHead']) { $requiredGit=[bool]$profile.policies.requireCleanPushedHead }
    $preservePreview = $true
    if ($profile.PSObject.Properties['policies'] -and $profile.policies.PSObject.Properties['preserveRemotePreview']) { $preservePreview=[bool]$profile.policies.preserveRemotePreview }
    Write-GMTCheckpoint '发布预检开始' "project=$($profile.projectName) variants=$($selected.name -join ',') publish=$Publish"
    $gitFacts = if ($requiredGit) {
        Get-GMTGitFacts -RepositoryRoot $projectRoot -Proxy $Proxy -Required $true
    } else {
        [ordered]@{ Required=$false }
    }
    $hasHooks = $profile.PSObject.Properties['hooks'] -and $profile.hooks
    if (-not $SkipVerify -and $hasHooks) {
        foreach ($hook in @($profile.hooks | Where-Object { $_.phase -eq 'verify' -and (-not $_.PSObject.Properties['variant'] -or $selected.name -contains $_.variant) })) {
            Push-Location $projectRoot; try { Invoke-GMTHook $hook $projectRoot } finally { Pop-Location }
        }
    }
    if ($SkipVerify -and $hasHooks) {
        foreach ($hook in @($profile.hooks | Where-Object { $_.phase -eq 'build' -and (-not $_.PSObject.Properties['variant'] -or $selected.name -contains $_.variant) })) {
            Push-Location $projectRoot; try { Invoke-GMTHook $hook $projectRoot } finally { Pop-Location }
        }
    }
    $remoteModule = if ($RemoteProviderPath) { (Resolve-Path -LiteralPath $RemoteProviderPath).Path } else { Join-Path $PSScriptRoot 'SteamRemoteProvider.psm1' }
    Import-Module $remoteModule -Force
    $notes = @{}
    if ($ChangeNotesFile) {
        $noteObject = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $ChangeNotesFile) | ConvertFrom-Json
        foreach ($property in $noteObject.PSObject.Properties) { $notes[$property.Name]=[string]$property.Value }
    }
    $items = [ordered]@{}
    foreach ($item in $selected) {
        if ($Publish -and [string]::IsNullOrWhiteSpace($notes[$item.name])) { throw "发布 $($item.name) 时必须提供更新说明。" }
        $facts = Get-GMTVariantFacts $item $projectRoot
        $before = Get-GMTRemoteWorkshopItem -PublishedFileId ([string]$item.publishedFileId) -Proxy $Proxy
        if ($before.title -ne $item.expectedTitle) { throw "Workshop 项目身份不匹配：expected=$($item.expectedTitle) actual=$($before.title)" }
        $remotePreviewPath = Join-Path $evidenceRoot "$($item.name)-preview-before.png"
        $remoteHash = Save-GMTRemotePreview -Details $before -TargetPath $remotePreviewPath -Proxy $Proxy
        if ($preservePreview -and $remoteHash -ne $facts.PreviewSha256) { throw "候选预览图与远端不一致：local=$($facts.PreviewSha256) remote=$remoteHash" }
        $facts.RemotePreviewPath=$remotePreviewPath; $facts.RemotePreviewSha256=$remoteHash
        $items[$item.name]=[ordered]@{ Variant=$item; Facts=$facts; Before=$before; ChangeNotes=$notes[$item.name] }
        Write-GMTCheckpoint "$($item.name) 预检完成" "id=$($item.publishedFileId) version=$($facts.Version) preview=$remoteHash"
    }
    $manifest = [ordered]@{ SchemaVersion=1; GeneratedAt=(Get-Date).ToString('o'); Publish=[bool]$Publish; Project=$profile.projectName; Git=$gitFacts; Items=$items }
    $manifestPath=Join-Path $evidenceRoot 'release-manifest.json'
    $manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    if (-not $Publish) { Write-GMTCheckpoint '只读预检完成' "manifest=$manifestPath"; Write-Output 'WORKSHOP_PUBLISH_PREFLIGHT=OK'; return }
    $adapterModule=Resolve-GMTAdapterPath $profile.adapter.id $AdapterPath
    Import-Module $adapterModule -Force
    $configuration = if ($profile.adapter.PSObject.Properties['configuration']) { $profile.adapter.configuration } else { [pscustomobject]@{} }
    if ($UploaderPath) { $configuration | Add-Member -NotePropertyName uploaderPath -NotePropertyValue $UploaderPath -Force }
    $session=Open-GMTWorkshopUploader -Configuration $configuration -EvidenceRoot $evidenceRoot
    try {
        foreach ($entry in $items.GetEnumerator()) {
            Open-GMTWorkshopProject -Session $session -Item $entry.Value -EvidenceRoot $evidenceRoot
            # 此调用点是整个通用编排器中唯一允许触发上传的边界。
            Invoke-GMTWorkshopUploadOnce -Session $session -Item $entry.Value -EvidenceRoot $evidenceRoot
            $timeout = if ($configuration.PSObject.Properties['uploadTimeoutSeconds']) { [int]$configuration.uploadTimeoutSeconds } else { 150 }
            $after=Wait-GMTWorkshopRemoteUpdate -PublishedFileId $entry.Value.Variant.publishedFileId -Before $entry.Value.Before -Proxy $Proxy -TimeoutSeconds $timeout
            if ($after.title -ne $entry.Value.Variant.expectedTitle) { throw '上传后远端标题发生变化。' }
            $afterPath=Join-Path $evidenceRoot "$($entry.Key)-preview-after.png"
            $afterHash=Save-GMTRemotePreview -Details $after -TargetPath $afterPath -Proxy $Proxy
            if ($preservePreview -and $afterHash -ne $entry.Value.Facts.RemotePreviewSha256) { throw '上传后远端预览图发生变化。' }
        }
    } finally { Close-GMTWorkshopUploader -Session $session }
    if ($requiredGit -and (Invoke-GMTGit $projectRoot @('status','--porcelain'))) { throw '发布后项目工作树发生变化。' }
    Write-GMTCheckpoint 'Workshop 自动发布完成' "evidence=$evidenceRoot"
    Write-Output 'WORKSHOP_PUBLISH=OK'
}

Export-ModuleMember -Function Invoke-GMTWorkshopRelease
