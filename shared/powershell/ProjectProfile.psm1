Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GMTToolkitRoot {
    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

function Get-GMTProjectProfileSchemaPath {
    return Join-Path (Get-GMTToolkitRoot) 'capabilities\publishing\steam-workshop\schemas\project-profile.schema.json'
}

function Read-GMTValidatedProjectProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $json = Get-Content -Raw -LiteralPath $resolved -Encoding UTF8
    $schema = Get-GMTProjectProfileSchemaPath
    if (-not ($json | Test-Json -SchemaFile $schema -ErrorAction Stop)) {
        throw "项目配置未通过 Schema 验证：$resolved"
    }
    $profile = $json | ConvertFrom-Json -Depth 32
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($variant in @($profile.variants)) {
        if (-not $names.Add([string]$variant.name)) { throw "变体名称重复：$($variant.name)" }
    }
    $hooks = if ($profile.PSObject.Properties['hooks']) { @($profile.hooks) } else { @() }
    foreach ($hook in $hooks) {
        if ($hook.PSObject.Properties['variant'] -and -not $names.Contains([string]$hook.variant)) {
            throw "发布钩子引用了不存在的变体：$($hook.variant)"
        }
    }
    return [ordered]@{ Path=$resolved; Directory=Split-Path $resolved -Parent; Value=$profile }
}

Export-ModuleMember -Function Get-GMTToolkitRoot,Get-GMTProjectProfileSchemaPath,Read-GMTValidatedProjectProfile
