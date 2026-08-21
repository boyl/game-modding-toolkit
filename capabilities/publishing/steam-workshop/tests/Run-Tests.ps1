$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
if($PSVersionTable.PSVersion.Major -lt 7){throw '测试需要 PowerShell 7。'}
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw "断言失败：$Message"}}
$capability=Split-Path $PSScriptRoot -Parent
$entry=Join-Path $capability 'Invoke-WorkshopRelease.ps1'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gmt-test-'+[guid]::NewGuid().ToString('N'))
try{
  $candidate=Join-Path $temp 'candidate'; New-Item -ItemType Directory -Path $candidate -Force|Out-Null
  '<metadata><name>Fake Mod</name><id>123</id><version>1.0.0</version></metadata>' | Set-Content -LiteralPath (Join-Path $candidate 'metadata.xml') -Encoding utf8
  [IO.File]::WriteAllBytes((Join-Path $candidate 'preview.png'),[byte[]](1,2,3,4,5))
  $profile=@{
    schemaVersion=1;projectName='fake-project';projectRoot='.';evidenceDirectory='artifacts';
    adapter=@{id='fake'};policies=@{requireCleanPushedHead=$false;preserveRemotePreview=$true};
    variants=@(@{name='test';publishedFileId='123';expectedTitle='Fake Mod';descriptionMarker='stable-marker';candidateDirectory='candidate'})
  }
  $profilePath=Join-Path $temp 'profile.json'; $profile|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $profilePath -Encoding utf8
  $notesPath=Join-Path $temp 'notes.json'; @{test='Test release'}|ConvertTo-Json|Set-Content -LiteralPath $notesPath -Encoding utf8
  $env:GMT_FAKE_PREVIEW_PATH=Join-Path $candidate 'preview.png'
  $env:GMT_FAKE_UPLOAD_LOG=Join-Path $temp 'uploads.log'
  $remote=Join-Path $PSScriptRoot 'fakes\FakeRemoteProvider.psm1'; $adapter=Join-Path $PSScriptRoot 'fakes\FakeUploaderAdapter.psm1'
  $readOnly=& $entry -ProjectProfile $profilePath -RemoteProviderPath $remote -AdapterPath $adapter 6>&1
  Assert-True (($readOnly -join "`n") -match 'WORKSHOP_PUBLISH_PREFLIGHT=OK') '默认应完成只读预检'
  Assert-True (-not (Test-Path -LiteralPath $env:GMT_FAKE_UPLOAD_LOG)) '只读预检不得触发上传'
  $published=& $entry -ProjectProfile $profilePath -RemoteProviderPath $remote -AdapterPath $adapter -Publish -ChangeNotesFile $notesPath 6>&1
  Assert-True (($published -join "`n") -match 'WORKSHOP_PUBLISH=OK') '显式发布应完成'
  $uploads=@(Get-Content -LiteralPath $env:GMT_FAKE_UPLOAD_LOG)
  Assert-True ($uploads.Count -eq 1) '每个变体上传触发必须严格等于一次'
  Assert-True ($uploads[0] -eq 'test') '上传变体必须正确'
  $source=Get-Content -Raw -LiteralPath (Join-Path $capability 'src\WorkshopRelease.psm1')
  Assert-True (([regex]::Matches($source,'Invoke-GMTWorkshopUploadOnce -Session')).Count -eq 1) '编排器只能有一个上传触发调用点'
  Write-Output 'STEAM_WORKSHOP_TESTS=OK'
}finally{
  Remove-Item Env:GMT_FAKE_PREVIEW_PATH -ErrorAction SilentlyContinue; Remove-Item Env:GMT_FAKE_UPLOAD_LOG -ErrorAction SilentlyContinue
  if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}

