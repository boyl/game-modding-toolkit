$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
& (Join-Path $root 'capabilities\publishing\steam-workshop\tests\Run-Tests.ps1')
& (Join-Path $root 'games\the-binding-of-isaac\tests\Run-Tests.ps1')
& (Join-Path $root 'games\monster-hunter-rise\tests\Run-Tests.ps1')
& (Join-Path $root 'tests\Run-AIIntegrationTests.ps1')
Write-Output 'GAME_MODDING_TOOLKIT_TESTS=OK'
