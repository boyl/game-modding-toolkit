# 通用验收能力

三个独立 PowerShell 7 入口：场景编排、布局诊断、制品证据门禁。它们不依赖 Codex，不启动游戏、不负责上传，不假定具体引擎。诊断和门禁为只读；仅指定 ReportPath 时写报告且拒绝覆盖。

## 使用

```powershell
pwsh ./Test-OverlayLayout.ps1 -Layout ./examples/layout.example.json
pwsh ./Test-AcceptedArtifact.ps1 -Artifact ./candidate.dll -Acceptance ./acceptance.json -EvidenceRoot ./evidence -SourceCommit <完整HEAD> -RuntimeEvidence ./runtime.json -InstalledArtifact <已安装DLL>
pwsh ./Invoke-AcceptanceScenarios.ps1 -Profile ./scenarios.json -AdapterModule ./GameAdapter.psm1 -Artifact ./candidate.dll -SourceCommit <完整HEAD> -OutputDirectory ./new-evidence -Run
```

场景执行需要显式 `-Run`，输出目录必须不存在。适配器是受信任的本地代码；不要加载下载的未知模块。JSON只包含数据，不接受Shell命令。

## 场景适配器契约

模块必须导出以下五个函数，返回普通 hashtable：

- `Save-AcceptanceState`：保存原设置，返回恢复所需状态；尚未成功保存时不要改变设置。
- `Enter-AcceptanceScenario -Scenario <hashtable>`：进入指定场景，场景可附带项目专属数据，不盲发输入。
- `Get-AcceptanceObservation`：返回 `ready`、`runtimeId`、`artifactSha256` 和标量字典 `values`。身份须来自正在运行的实际副本，不能复制候选配置中的预期值。
- `Save-AcceptanceEvidence -OutputDirectory <新目录>`：保存截图、探针快照等，返回证据文件的完整路径；文件必须在本轮证据目录内。
- `Restore-AcceptanceState -State <保存状态>`：恢复所有临时设置并验证恢复成功；恢复未成功必须抛出异常。

编排器先保存，进入场景后按实际ready状态推进，最长等待由profile限定。对预期状态逐项断言，错误身份立即失败。失败时停止后续场景，在finally恢复设置并保存report.json。恢复失败阻止通过。报告的kind固定为automated，不产生人工视觉验收结果。

## 布局快照

输入必须来自实际渲染器的共享矩形和翻译后字体测量。坐标均为画布本地坐标；textBounds包含控件内边距，layer数值越大表示越晚绘制。只提供文本、控件等互斥叶元素，不把容器背景作为普通content元素。

工具检查文字裁切、画布越界、普通内容重叠、弹出菜单层级和背景输入归属。正确前景popup可以遮挡普通内容。背景可见但不接收输入。PNG本身不能证明命中区域或字体测量；本工具也不判断美观、颜色对比和真实字形，仍需人工看图。

## 制品验收门禁

候选文件哈希、来源提交、运行时加载身份必须匹配；指定安装副本时同时核对其哈希。每个必需check必须passed并绑定当前候选及存在且哈希正确的证据。旧版passed、空证据、路径越界、符号链接、失败/未验证记录不能放行。

kind区分automated、simulation、runtime、manual；项目验收文档决定哪些证据类型必须具备。simulation不等于runtime或manual。工具验证证据的绑定与完整性，不证明声明真实；运行时探针和人工判断属于项目适配器/验收者职责。远端分支、标签和下载附件验证仍由发布能力完成。

配置契约见schemas；结构错误直接失败。examples使用占位哈希，不能直接充当真实验收。

## 验证范围

运行 `tests/Run-Tests.ps1`，覆盖场景恢复、超时、错误身份、观察断言、几何裁切、层级、输入冲突及旧证据阻断。测试适配器属于模拟，并未据此声称支持某个真实游戏。
