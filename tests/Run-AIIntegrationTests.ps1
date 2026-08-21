$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw "断言失败：$Message"}}
$root=Split-Path $PSScriptRoot -Parent
$generator=Join-Path $root 'New-ModProjectProfile.ps1'
$doctor=Join-Path $root 'Test-ModdingToolkitEnvironment.ps1'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gmt-ai-test-'+[guid]::NewGuid().ToString('N'))
try {
    $candidate=Join-Path $temp 'candidate'; New-Item -ItemType Directory -Path $candidate -Force|Out-Null
    '<metadata><name>Fake Mod</name><id>123</id><version>1.0.0</version></metadata>'|Set-Content -LiteralPath (Join-Path $candidate 'metadata.xml') -Encoding utf8
    [IO.File]::WriteAllBytes((Join-Path $candidate 'preview.png'),[byte[]](1,2,3))
    $uploader=Join-Path $temp 'ModUploader.exe'; [IO.File]::WriteAllBytes($uploader,[byte[]](77,90))
    $profilePath=Join-Path $temp 'profile.json'
    $variant=@{name='test';publishedFileId='123';expectedTitle='Fake Mod';descriptionMarker='marker';candidateDirectory='candidate'}
    $generated=& $generator -Game the-binding-of-isaac -ProjectRoot $temp -OutputPath $profilePath -ProjectName fake -Variant @($variant) 6>&1
    Assert-True (($generated -join "`n") -match 'GAME_MODDING_TOOLKIT_PROFILE=OK') '生成器应输出稳定成功标记'
    Assert-True (Test-Path -LiteralPath $profilePath -PathType Leaf) '生成器应创建配置'
    $schema=Join-Path $root 'capabilities\publishing\steam-workshop\schemas\project-profile.schema.json'
    Assert-True ((Get-Content -Raw -LiteralPath $profilePath|Test-Json -SchemaFile $schema)) '生成配置必须通过完整 Schema'
    $generatedProfile=Get-Content -Raw -LiteralPath $profilePath|ConvertFrom-Json
    Assert-True ([bool]$generatedProfile.policies.requireCleanPushedHead) '生成器默认必须启用 Git 门禁'
    Assert-True ([bool]$generatedProfile.policies.preserveRemotePreview) '生成器默认必须保护远端预览图'
    $overwriteRejected=$false; try{& $generator -Game the-binding-of-isaac -ProjectRoot $temp -OutputPath $profilePath -ProjectName fake -Variant @($variant) 2>$null|Out-Null}catch{$overwriteRejected=$true}
    Assert-True $overwriteRejected '生成器默认必须拒绝覆盖'

    $generatedProfile.policies.requireCleanPushedHead=$false
    $generatedProfile|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $profilePath -Encoding utf8
    $before=@(Get-Process ModUploader -ErrorAction SilentlyContinue).Count
    $diagnosed=& $doctor -ProjectProfile $profilePath -UploaderPath $uploader 6>&1
    $after=@(Get-Process ModUploader -ErrorAction SilentlyContinue).Count
    Assert-True (($diagnosed -join "`n") -match 'GAME_MODDING_TOOLKIT_DOCTOR=OK') '诊断器应输出稳定成功标记'
    Assert-True ($before -eq $after) '诊断器不得启动上传器'
    $head=(& git -C $root rev-parse HEAD).Trim()
    $lockPath=Join-Path $temp 'toolkit.lock.json'
    @{repository='https://github.com/boyl/game-modding-toolkit';minimumVersion='0.2.0';verifiedCommit=$head}|ConvertTo-Json|Set-Content -LiteralPath $lockPath -Encoding utf8
    $locked=& $doctor -ProjectProfile $profilePath -ToolkitLock $lockPath -UploaderPath $uploader -Json 6>&1
    $lockedResult=($locked -join "`n")|ConvertFrom-Json
    Assert-True ($lockedResult.successMarker -eq 'GAME_MODDING_TOOLKIT_DOCTOR=OK') '匹配的版本锁必须通过并提供机器标记'
    $badLock=Get-Content -Raw -LiteralPath $lockPath|ConvertFrom-Json; $badLock.verifiedCommit='0000000000000000000000000000000000000000'; $badLock|ConvertTo-Json|Set-Content -LiteralPath $lockPath -Encoding utf8
    $lockRejected=$false; try{& $doctor -ProjectProfile $profilePath -ToolkitLock $lockPath -UploaderPath $uploader -Json 2>$null 6>$null|Out-Null}catch{$lockRejected=$true}
    Assert-True $lockRejected '提交 SHA 不匹配的版本锁必须失败'

    $missingRejected=$false; try{& $doctor -ProjectProfile $profilePath -UploaderPath (Join-Path $temp 'missing\ModUploader.exe') 2>$null 6>$null|Out-Null}catch{$missingRejected=$true}
    Assert-True $missingRejected '缺少上传器时诊断必须失败'
    $invalid=Get-Content -Raw -LiteralPath $profilePath|ConvertFrom-Json; $invalid|Add-Member unexpected true
    $invalidPath=Join-Path $temp 'invalid.json'; $invalid|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $invalidPath -Encoding utf8
    $schemaRejected=$false; try{& $doctor -ProjectProfile $invalidPath -UploaderPath $uploader 2>$null|Out-Null}catch{$schemaRejected=$true}
    Assert-True $schemaRejected '额外字段必须被 Schema 拒绝'

    $rootAgents=Get-Content -Raw -LiteralPath (Join-Path $root 'AGENTS.md')
    Assert-True ($rootAgents -notmatch 'Isaac|ModUploader|窗口标题|相对坐标') '根规则不得包含游戏专属细节'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'capabilities\publishing\steam-workshop\AGENTS.md')) '能力规则必须独立存在'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'games\the-binding-of-isaac\AGENTS.md')) '游戏规则必须独立存在'
    Write-Output 'AI_INTEGRATION_TESTS=OK'
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
