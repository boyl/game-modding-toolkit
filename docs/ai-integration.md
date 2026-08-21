# AI 接入指南

本工具可由 Codex、Claude Code、GitHub Copilot 等能够读取仓库并运行 PowerShell 7 的编码代理使用，不依赖特定 AI、插件或 Skill。

## 固定工作流

1. 读取根 `AGENTS.md`，再读取目标能力和游戏目录的 `AGENTS.md`。
2. 读取对应游戏 README，确认系统要求和项目配置。
3. 运行 `Test-ModdingToolkitEnvironment.ps1`。缺少配置时先用 `New-ModProjectProfile.ps1` 生成。
4. 不带 `-Publish` 运行 Workshop 入口，检查 `release-manifest.json`。
5. 向用户报告变体、Workshop 身份、Git SHA、候选版本、预览图哈希和证据目录。
6. 只有用户明确授权“发布”后，才允许传递 `-Publish` 和更新说明。
7. 发布后核对证据和远端结果；状态不明或超时时不得重复触发 Upload。

成功诊断输出 `GAME_MODDING_TOOLKIT_DOCTOR=OK`，成功预检输出 `WORKSHOP_PUBLISH_PREFLIGHT=OK`，成功发布输出 `WORKSHOP_PUBLISH=OK`。缺少任一成功标记均不得推断操作成功。

## 可复制提示词

### 接入现有 Mod

> 请读取 game-modding-toolkit 根目录、Steam Workshop 能力目录和对应游戏目录的 AGENTS.md 与 README。先运行环境诊断；若项目没有配置，使用配置生成器创建并验证。随后只运行只读预检，汇报 Git SHA、变体、Workshop 身份、候选版本、预览图哈希和证据目录。不要发布，也不要写入凭据或个人信息。

### 发布已配置项目

> 请遵循 game-modding-toolkit 的分层 AGENTS.md。先运行环境诊断和只读预检并核对证据；只有两者成功后，发布我明确指定的变体。每个变体最多触发一次 Upload，超时不得重试，并在结束后核对远端结果。

## 失败原则

- 配置、工具版本锁、项目身份或预览图不匹配时停止，不自动修正真实项目身份。
- 缺少 Steam 登录、上传器或前台 GUI 权限时报告恢复步骤，不使用其他凭据或上传工具替代。
- 未得到明确发布授权时，即使预检通过也必须停留在只读状态。
