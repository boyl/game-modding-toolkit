# Steam Workshop 发布能力

公共入口为 `Invoke-WorkshopRelease.ps1`。它读取版本化项目配置，执行 Git、构建、Steam 远端和预览图门禁，并把真实 GUI 上传委托给游戏适配器。

默认只执行只读预检。`-Publish` 是唯一允许进入远端变更状态的开关；每个变体一次运行最多触发一次上传，触发后只轮询远端状态。默认运行 `verify` 钩子；`-SkipVerify` 会改为运行 `build` 钩子。

详细的 Isaac 配置和发布方式见 [Isaac 指南](../../../games/the-binding-of-isaac/README.md)。
