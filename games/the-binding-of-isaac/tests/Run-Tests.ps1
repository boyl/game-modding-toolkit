$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$module=Join-Path (Split-Path $PSScriptRoot -Parent) 'adapters\mod-uploader\IsaacModUploaderAdapter.psm1'
$content=Get-Content -Raw -LiteralPath $module
foreach($name in 'Test-GMTWorkshopAdapterEnvironment','Open-GMTWorkshopUploader','Open-GMTWorkshopProject','Invoke-GMTWorkshopUploadOnce','Close-GMTWorkshopUploader'){
  if($content -notmatch [regex]::Escape($name)){throw "适配器缺少契约函数：$name"}
}
if(([regex]::Matches($content,'Click-GMTIsaacRelative \$main 0\.26 0\.16')).Count -ne 1){throw '上传按钮坐标必须只有一个调用点。'}
if($content -notmatch '每个动作前重新枚举'){throw '缺少重新获取窗口焦点门禁。'}
if($content -match 'publishedFileId\s*=\s*["'']?\d+' -or $content -match 'C:\\Users\\'){throw '公共适配器包含项目 ID 或个人路径。'}
Write-Output 'ISAAC_ADAPTER_TESTS=OK'
