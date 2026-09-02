#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw "目标已存在，拒绝覆盖：$output" }

$validation = & (Join-Path $PSScriptRoot 'Test-WeaponVfxProfile.ps1') -ProfilePath $ProfilePath -PassThru
$profileResult = @($validation | Where-Object { $_ -is [pscustomobject] })[0]
if ($null -eq $profileResult) { throw 'Profile 验证没有返回结构化结果。' }

if ($PSCmdlet.ShouldProcess($output, '创建 MHRise 武器 VFX 项目骨架')) {
    [IO.Directory]::CreateDirectory((Join-Path $output 'config')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $output 'assets')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $output 'runtime-adapter')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $output 'tests')) | Out-Null
    Copy-Item -LiteralPath ([IO.Path]::GetFullPath($ProfilePath)) -Destination (Join-Path $output 'config\weapon-vfx-profile.json')
    @(
        "# $($profileResult.ProfileId)"
        ''
        '该目录由 game-modding-toolkit 的 MHRise 武器 VFX 生成器创建。'
        ''
        '- `config/`：武器身份与动作配方。'
        '- `assets/`：仅放项目合法持有的修改后 VFX 资源。'
        '- `runtime-adapter/`：目标版本的 REFramework/yun 适配器。'
        '- `tests/`：动作、生命周期、包清单和实机证据。'
        ''
        '先完成三条 MVP 动作的空击、命中和实例释放验收，再扩充完整动作表。'
    ) | Set-Content -LiteralPath (Join-Path $output 'README.md') -Encoding utf8NoBOM
    [ordered]@{
        generated_by = 'game-modding-toolkit'
        capability = 'mhrise-weapon-vfx'
        profile_id = $profileResult.ProfileId
        schema_version = 1
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'toolkit-lock.json') -Encoding utf8NoBOM
    "MHR_WEAPON_VFX_PROJECT=$output"
}
