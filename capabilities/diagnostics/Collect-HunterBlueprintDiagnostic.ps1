#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GamePath,
    [Parameter(Mandatory)][string]$ReleaseArchive,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'PlayerDiagnostics.psm1') -Force
$game=Resolve-DiagnosticPath $GamePath
$output=Resolve-DiagnosticPath $OutputDirectory
$gamePrefix=$game.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
if($output.Equals($game,[StringComparison]::OrdinalIgnoreCase) -or $output.StartsWith($gamePrefix,[StringComparison]::OrdinalIgnoreCase)){throw '输出目录必须位于游戏目录之外。'}
if(Test-Path -LiteralPath $output){throw '输出目录已存在；请使用新目录以保留已有证据。'}
if(!(Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($output)) -PathType Container)){throw '输出父目录不存在。'}
$manifest=Read-HunterManifest $ReleaseArchive
$report=New-HunterDiagnosticReport -GamePath $game -Manifest $manifest
New-Item -ItemType Directory -Path $output | Out-Null
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $output 'report.json') -Encoding utf8NoBOM
$summary=@"
猎人蓝图只读诊断
目标发布版本：$($report.expectedVersion)
安装文件：$($report.installation)（matched=匹配；mismatch=有缺失、不符、不可读或残留 Lua）
残留 Lua 数量：$($report.extraLuaCount)
游戏主程序存在：$($report.gameExecutablePresent)
游戏版本：$($report.gameVersion)
框架版本：unknown（本工具未验证）
运行时状态：unknown（未执行任何游戏调用）
日志状态：$($report.logs.status)；读取字节：$($report.logs.bytesRead)；截断：$($report.logs.truncated)
固定类别事件数：$($report.logs.events.Count)

下一步：若安装不匹配，依据 report.json 的相对路径核对安装目录及对应版本；不要直接删除未知文件。
若游戏主程序不存在，请确认选择了真正的游戏根目录。
若日志缺失或不可读，请在复现后再次采集；本工具不会关闭游戏或解除文件占用。
文件一致不能证明界面、联机或功能正确。框架版本未知不代表框架未安装。
本包仅含此说明及结构化报告；没有原始日志、个人配置、存档或玩家身份。
日志仅末尾采样，最多输出 100 个固定类别事件；无事件不能证明没有错误。
输出基于所选本地发行包清单；不认证发行包来源。分享前仍可自行查看 report.json。
"@
$summary | Set-Content -LiteralPath (Join-Path $output '说明.txt') -Encoding utf8NoBOM
$zip=[IO.Compression.ZipFile]::Open((Join-Path $output 'diagnostic.zip'),'Create')
try{foreach($name in @('report.json','说明.txt')){[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $output $name),$name)}}finally{$zip.Dispose()}
Write-Output "采集完成：installation=$($report.installation)，runtime=unknown；诊断包已保存至指定输出目录。"
