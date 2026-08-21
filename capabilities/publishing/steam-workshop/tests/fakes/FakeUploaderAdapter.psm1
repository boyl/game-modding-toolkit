function Open-GMTWorkshopUploader { param($Configuration,[string]$EvidenceRoot) @{UploadCount=0;OpenCount=0} }
function Open-GMTWorkshopProject { param($Session,$Item,[string]$EvidenceRoot) $Session.OpenCount++ }
function Invoke-GMTWorkshopUploadOnce { param($Session,$Item,[string]$EvidenceRoot) $Session.UploadCount++; Add-Content -LiteralPath $env:GMT_FAKE_UPLOAD_LOG -Value $Item.Variant.name; if($Session.UploadCount -gt 1){throw '同一变体重复上传'} }
function Close-GMTWorkshopUploader { param($Session) }
Export-ModuleMember -Function Open-GMTWorkshopUploader,Open-GMTWorkshopProject,Invoke-GMTWorkshopUploadOnce,Close-GMTWorkshopUploader

