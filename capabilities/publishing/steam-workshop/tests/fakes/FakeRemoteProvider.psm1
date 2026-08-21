$script:PreviewPath=$env:GMT_FAKE_PREVIEW_PATH
function Get-GMTRemoteWorkshopItem { param([string]$PublishedFileId,[uri]$Proxy) [pscustomobject]@{result=1;publishedfileid=$PublishedFileId;title='Fake Mod';description='stable-marker';preview_url='fake://preview';time_updated=100} }
function Save-GMTRemotePreview { param($Details,[string]$TargetPath,[uri]$Proxy) Copy-Item -LiteralPath $script:PreviewPath -Destination $TargetPath; (Get-FileHash -Algorithm SHA256 -LiteralPath $TargetPath).Hash }
function Wait-GMTWorkshopRemoteUpdate { param([string]$PublishedFileId,$Before,[uri]$Proxy,[int]$TimeoutSeconds) [pscustomobject]@{result=1;publishedfileid=$PublishedFileId;title='Fake Mod';description='stable-marker';preview_url='fake://preview';time_updated=101} }
Export-ModuleMember -Function Get-GMTRemoteWorkshopItem,Save-GMTRemotePreview,Wait-GMTWorkshopRemoteUpdate

