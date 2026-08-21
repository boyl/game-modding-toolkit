Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:SteamApi = 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/'

function Get-GMTRemoteWorkshopItem {
    param([Parameter(Mandatory)][string]$PublishedFileId, [uri]$Proxy)
    $parameters = @{
        Method = 'Post'
        Uri = $script:SteamApi
        TimeoutSec = 20
        Body = "itemcount=1&publishedfileids[0]=$PublishedFileId"
    }
    if ($Proxy) { $parameters.Proxy = $Proxy }
    $response = Invoke-RestMethod @parameters
    $details = $response.response.publishedfiledetails | Select-Object -First 1
    if (-not $details -or $details.result -ne 1) {
        throw "Steam API 未返回有效项目：$PublishedFileId"
    }
    return $details
}

function Save-GMTRemotePreview {
    param([Parameter(Mandatory)]$Details, [Parameter(Mandatory)][string]$TargetPath, [uri]$Proxy)
    $parameters = @{ Uri = $Details.preview_url; TimeoutSec = 30; OutFile = $TargetPath }
    if ($Proxy) { $parameters.Proxy = $Proxy }
    Invoke-WebRequest @parameters
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $TargetPath).Hash
}

function Wait-GMTWorkshopRemoteUpdate {
    param(
        [Parameter(Mandatory)][string]$PublishedFileId,
        [Parameter(Mandatory)]$Before,
        [uri]$Proxy,
        [ValidateRange(10, 600)][int]$TimeoutSeconds = 150
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 2
        try { $after = Get-GMTRemoteWorkshopItem -PublishedFileId $PublishedFileId -Proxy $Proxy } catch { continue }
        if ([long]$after.time_updated -gt [long]$Before.time_updated) { return $after }
    } while ((Get-Date) -lt $deadline)
    throw "上传后远端更新时间未变化；为保证单次上传，没有再次触发上传：$PublishedFileId"
}

Export-ModuleMember -Function Get-GMTRemoteWorkshopItem, Save-GMTRemotePreview, Wait-GMTWorkshopRemoteUpdate
