# game-modding-toolkit

面向多游戏 Mod 的可分发工具集合，覆盖开发、验证、安装、诊断与发布。工具可在 PowerShell 7 中独立运行，不依赖 Codex 或 Skill。

编码代理可从 [AI 接入指南](docs/ai-integration.md) 开始；规则按仓库、能力和游戏分层组织，不依赖特定 AI 产品。

## 能力索引

- [Steam Workshop 发布](capabilities/publishing/steam-workshop/README.md)：只读预检、远端身份校验、预览图保护、单次上传状态机与发布证据。
- 预留分类：`packaging`、`installing`、`validation`、`diagnostics`。

## 支持游戏

- [The Binding of Isaac: Rebirth](games/the-binding-of-isaac/README.md)：使用游戏自带 `ModUploader.exe` 的 Windows GUI 适配器。

首版仅正式支持 Windows 与 PowerShell 7。其他游戏可复用通用发布能力，但必须实现并测试自己的适配器。

## 快速开始

```powershell
pwsh ./capabilities/publishing/steam-workshop/Invoke-WorkshopRelease.ps1 `
  -ProjectProfile ./games/the-binding-of-isaac/examples/project-profile.example.json
```

命令默认只读。只有显式添加 `-Publish` 并提供更新说明，才会改变远端 Workshop 项目。

首次接入项目可先运行配置生成器和环境诊断器：

```powershell
pwsh ./New-ModProjectProfile.ps1 -Game the-binding-of-isaac -ProjectRoot C:/path/to/mod -OutputPath C:/path/to/mod/tools/workshop-release-profile.json -Variant $variants
pwsh ./Test-ModdingToolkitEnvironment.ps1 -ProjectProfile C:/path/to/mod/tools/workshop-release-profile.json
```

更多入口见 [文档索引](docs/README.md) 和 [Workshop 适配器契约](docs/adapter-contract.md)。

## 贡献与许可证

提交新能力时放入 `capabilities/<能力>/`；游戏专属实现放入 `games/<game>/`，不得把个人路径、凭据或真实 Workshop ID 写入公共示例。

本项目采用 [MIT License](LICENSE)。
