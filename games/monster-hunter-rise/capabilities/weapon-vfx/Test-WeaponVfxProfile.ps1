#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$capabilityRoot = $PSScriptRoot
$schemaPath = Join-Path $capabilityRoot 'schemas\weapon-vfx-profile.schema.json'
$resolvedProfile = [IO.Path]::GetFullPath($ProfilePath)
if (-not (Test-Path -LiteralPath $resolvedProfile -PathType Leaf)) {
    throw "找不到武器 VFX Profile：$resolvedProfile"
}

$raw = Get-Content -LiteralPath $resolvedProfile -Raw -Encoding UTF8
$schemaRaw = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8
$schemaErrors = $null
if (-not ($raw | Test-Json -Schema $schemaRaw -ErrorAction SilentlyContinue -ErrorVariable schemaErrors)) {
    $detail = @($schemaErrors | ForEach-Object Exception | ForEach-Object Message) -join '; '
    throw "Profile 不符合 v1 Schema：$detail"
}
$profile = $raw | ConvertFrom-Json

$seenActions = @{}
$persistent = @{}
foreach ($effectId in @($profile.effects.persistent_effect_ids)) {
    $persistent[[int]$effectId] = $true
}
foreach ($recipe in @($profile.recipes)) {
    $actionId = [int]$recipe.action_id
    if ($seenActions.ContainsKey($actionId)) { throw "动作 ID 重复：$actionId" }
    $seenActions[$actionId] = $true
    $whiffId = [int]$recipe.whiff_effect_id
    $hitId = [int]$recipe.hit_effect_id
    if ($persistent.ContainsKey($hitId)) {
        throw "命中特效必须是一次性效果，不能列为持续实例：$hitId"
    }
    if ([string]$recipe.whiff_mode -eq 'instance' -and -not $persistent.ContainsKey($whiffId)) {
        throw "instance 配方的空击 Effect ID 必须列入 persistent_effect_ids：$whiffId"
    }
    if ([string]$recipe.whiff_mode -eq 'one_shot' -and $persistent.ContainsKey($whiffId)) {
        throw "one_shot 配方不能派发持续实例 Effect ID：$whiffId"
    }
    $hasFinishEffect = $recipe.PSObject.Properties.Name -contains 'finish_effect_id'
    if ($hasFinishEffect -and $null -ne $recipe.finish_effect_id -and
        $persistent.ContainsKey([int]$recipe.finish_effect_id)) {
        throw "结束特效必须是一次性效果：$($recipe.finish_effect_id)"
    }
}

$baselineMissing = @($profile.effects.baseline_effect_ids | Where-Object {
    $id = [int]$_
    @($profile.recipes | Where-Object {
        [int]$_.whiff_effect_id -eq $id -or [int]$_.hit_effect_id -eq $id
    }).Count -eq 0
})
if ($baselineMissing.Count -gt 0) {
    throw "基准 Effect ID 未被任何配方引用：$($baselineMissing -join ', ')"
}

$result = [pscustomobject]@{
    ProfilePath = $resolvedProfile
    ProfileId = [string]$profile.profile_id
    WeaponType = [int]$profile.weapon.type_id
    ActionBank = [int]$profile.action.bank
    ContainerId = [int]$profile.effects.container_id
    RecipeCount = @($profile.recipes).Count
    PersistentEffectCount = @($profile.effects.persistent_effect_ids).Count
    NetworkSync = [bool]$profile.network_sync
}
if ($PassThru) { $result }
'MHR_WEAPON_VFX_PROFILE=OK'
