# 玩家只读诊断

首版支持猎人蓝图 Hunter Blueprint。需要 Windows、PowerShell 7 和可信的本地发行 ZIP；无第三方依赖。

```powershell
pwsh ./Collect-HunterBlueprintDiagnostic.ps1 -GamePath 'D:/SteamLibrary/steamapps/common/MonsterHunterRise' -ReleaseArchive 'D:/Downloads/HunterBlueprint-1.1.0.zip' -OutputDirectory 'D:/Reports/hunter-check-001'
```

先创建 Reports 父目录，末级 hunter-check-001 必须不存在且位于游戏目录外。不会覆盖已有结果。
打开说明.txt 和 report.json 查看结果；需要反馈时手动分享 diagnostic.zip。工具不联网、不自动上传、不启动或关闭游戏。

核对 ZIP 清单中的 Mod Lua/字体 SHA-256，并检查额外 Lua 残留。README 和许可证不用安装到游戏目录。
`matched` 只表示安装文件匹配所选清单，不能证明游戏已加载该版本。报告始终将运行时状态保留为 unknown。
游戏版本来自可执行文件数字版本；框架版本无法可靠确认，明确为 unknown。

只读 re2_framework_log.txt 末尾最多 256 KiB，分享包仅保留固定错误类别及采样内行号，最多 100 条。
不保存原文、完整堆栈、个人路径、玩家身份、配置、存档或其他 Mod 内容。没有匹配事件不等于没有故障。
输入路径中的重解析点拒绝；异常结构和越界清单在创建输出之前拒绝。不存在/不可读的日志是独立状态。

## 测试

```powershell
pwsh ./tests/Run-Tests.ps1 -WorkDirectory 'D:/Reports/diagnostic-tests-new'
```

测试目录必须不存在，保留合成故障证据。测试使用共享写入和独占文件句柄模拟运行中日志；这不等于游戏运行时验收。
