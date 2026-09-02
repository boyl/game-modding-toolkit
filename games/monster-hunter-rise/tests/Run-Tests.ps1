#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$gameRoot = Split-Path -Parent $PSScriptRoot
$capability = Join-Path $gameRoot 'capabilities\weapon-vfx'
$validator = Join-Path $capability 'Test-WeaponVfxProfile.ps1'
$generator = Join-Path $capability 'New-WeaponVfxProject.ps1'
$example = Join-Path $capability 'examples\weapon-profile.example.json'
$engine = Join-Path $capability 'runtime\WeaponVfxRuntime.lua'
$adapter = Join-Path $capability 'runtime\ReframeworkYunAdapter.lua'

$result = & $validator -ProfilePath $example -PassThru
if (@($result | Where-Object { $_ -eq 'MHR_WEAPON_VFX_PROFILE=OK' }).Count -ne 1) {
    throw '示例 Profile 未通过验证。'
}
$profileResult = @($result | Where-Object { $_ -is [pscustomobject] })[0]
if ($profileResult.RecipeCount -ne 2 -or $profileResult.NetworkSync -ne $false) {
    throw 'Profile 结构化验证结果错误。'
}

$engineText = Get-Content -LiteralPath $engine -Raw -Encoding UTF8
$adapterText = Get-Content -LiteralPath $adapter -Raw -Encoding UTF8
foreach ($required in @(
    'function Runtime.start(profile, adapter, reporter)',
    'release_instances(changed and "action-changed"',
    'release_instances("script-reset")',
    'adapter.authorize_hit(raw_hit, profile)',
    'profile.weapon.type_id',
    'profile.action.bank',
    'profile.effects.container_id'
)) {
    if (-not $engineText.Contains($required)) { throw "通用引擎缺少契约：$required" }
}
foreach ($forbidden in @('ShortSword', 'EXPECTED_WEAPON_TYPE = 8', 'EXPECTED_ACTION_BANK = 100', 'EXPECTED_CONTAINER_ID = 150')) {
    if ($engineText.Contains($forbidden)) { throw "通用引擎包含片手硬编码：$forbidden" }
}
if ([regex]::Matches($adapterText, 'sdk\.hook\(').Count -ne 1 -or
    -not $adapterText.Contains('network effect dispatch is forbidden') -or
    -not $adapterText.Contains('instance:finishAll()') -or
    -not $adapterText.Contains('instance:force_release()')) {
    throw 'REFramework/yun 适配器没有满足单 Hook、本地派发和实例释放契约。'
}

$testRoot = Join-Path $gameRoot '.test-work\weapon-vfx'
$resolvedGameRoot = [IO.Path]::GetFullPath($gameRoot).TrimEnd('\')
$resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
if (-not $resolvedTestRoot.StartsWith($resolvedGameRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw '测试目录越界。'
}
if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
try {
    $generated = Join-Path $testRoot 'generated-project'
    & $generator -ProfilePath $example -OutputDirectory $generated | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $generated 'config\weapon-vfx-profile.json') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $generated 'toolkit-lock.json') -PathType Leaf)) {
        throw '项目生成器没有生成最小骨架。'
    }

    $invalid = Get-Content -LiteralPath $example -Raw | ConvertFrom-Json
    $invalid.network_sync = $true
    $invalidPath = Join-Path $testRoot 'invalid-network.json'
    $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidPath -Encoding utf8NoBOM
    $failed = $false
    try { & $validator -ProfilePath $invalidPath | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw '验证器没有拒绝 network_sync=true。' }

    $lifecycle = Get-Content -LiteralPath $example -Raw | ConvertFrom-Json
    $lifecycle.recipes[0].whiff_effect_id = 24021
    $lifecyclePath = Join-Path $testRoot 'invalid-lifecycle.json'
    $lifecycle | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $lifecyclePath -Encoding utf8NoBOM
    $failed = $false
    try { & $validator -ProfilePath $lifecyclePath | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw '验证器没有拒绝 one_shot 使用持续 Effect ID。' }
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

'MHR_WEAPON_VFX_TESTS=OK'
