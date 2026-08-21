# The Binding of Isaac：Steam Workshop 发布

这是本仓库首个正式游戏适配器。它调用游戏随附的 `ModUploader.exe`，在每个 GUI 动作前重新枚举、前置并验证窗口，使用窗口相对坐标适配 DPI 和窗口移动，并确保每个变体的上传按钮至多点击一次。

## 支持范围与要求

- Windows 10/11 与 PowerShell 7。
- The Binding of Isaac: Rebirth 的 Repentance、Repentance+ 或 REPENTOGON Mod 项目。
- 游戏随附的 `ModUploader.exe`；工具会从 Steam 库定位，也可显式指定路径。
- Steam 客户端保持登录；发布前确保上传器能够正常打开。
- Git 项目默认要求工作树干净，且当前 HEAD 已推送到 `origin`。

工具不保存 Steam 凭据，也不会自动联网安装自身。示例不含真实 Workshop ID、个人目录或代理地址。

## 直接运行

克隆仓库后，复制并修改 [`examples/project-profile.example.json`](examples/project-profile.example.json)：

```powershell
pwsh ./capabilities/publishing/steam-workshop/Invoke-WorkshopRelease.ps1 `
  -ProjectProfile C:/path/to/your-project/tools/workshop-release-profile.json
```

默认只读预检；它会构建或验证候选、检查 Git、读取 Steam 项目、下载远端预览图并生成证据，不会打开上传器或修改远端。

## 配置字段

- `schemaVersion`：当前固定为 `1`。
- `projectRoot`：相对于配置文件的项目根目录，也可用绝对路径。
- `evidenceDirectory`：相对于项目根目录的证据目录。
- `adapter.id`：Isaac 固定为 `isaac-mod-uploader`。
- `adapter.configuration.mainWindowTitle`：上传器窗口标题；通常无需修改。
- `adapter.configuration.uploadTimeoutSeconds`：上传后只读轮询的最长秒数。
- `policies.requireCleanPushedHead`：是否要求干净且已推送的 Git HEAD。
- `policies.preserveRemotePreview`：是否要求候选预览图与远端完全一致。
- `hooks`：固定的 `executable` 与 `arguments` 数组，不接受拼接的任意 shell 字符串。默认运行 `verify`；使用 `-SkipVerify` 时跳过验证并改为运行 `build`，用于保留项目原有的快速候选构建流程。
- `variants`：语言或发行变体。每项包含名称、Workshop ID、预期标题、描述标记和候选目录。

## 发布一个或多个语言版本

先创建更新说明 JSON：

```json
{
  "zh": "修复输入问题。",
  "en": "Fixed an input issue."
}
```

仅发布中文：

```powershell
pwsh ./capabilities/publishing/steam-workshop/Invoke-WorkshopRelease.ps1 `
  -ProjectProfile ./tools/workshop-release-profile.json `
  -Variant zh -Publish -ChangeNotesFile ./tools/change-notes.user.json
```

连续发布配置中的全部变体：

```powershell
pwsh ./capabilities/publishing/steam-workshop/Invoke-WorkshopRelease.ps1 `
  -ProjectProfile ./tools/workshop-release-profile.json `
  -Publish -ChangeNotesFile ./tools/change-notes.user.json
```

上传触发后，工具只轮询 Steam API；即使 API 延迟或超时，也不会再次点击 Upload。证据目录包含远端预览图、上传器截图和 `release-manifest.json`。

## 远端预览图保护

预检会下载远端预览图并与候选 `preview.png` 比较 SHA-256。发布时上传器选择下载得到的远端图片，而不是盲目覆盖；发布后再次下载并核对。若哈希不同，流程在上传前失败。

## 可选当前用户安装

运行根目录的 `Install-CurrentUser.ps1` 可把当前版本安装到当前用户 PowerShell 模块目录。项目兼容入口可按以下顺序发现工具：显式路径、`GAME_MODDING_TOOLKIT_ROOT`、当前用户模块、约定相邻仓库。

## 为另一个 Isaac Mod 建立配置

1. 为每个语言或发行变体准备独立候选目录。
2. 在配置中填写真实 Workshop ID、预期标题和描述中稳定存在的标记。
3. 用固定参数数组声明构建与验证脚本。
4. 先运行只读预检并检查清单、版本、远端更新时间和预览图哈希。
5. 只有预检完全符合预期后才添加 `-Publish`。

也可以让配置生成器创建安全默认值：

```powershell
$variants = @(
  @{ name='zh'; publishedFileId='0000000000'; expectedTitle='示例标题'; descriptionMarker='稳定描述标记'; candidateDirectory='dist/workshop-candidates/zh' }
)
pwsh ./New-ModProjectProfile.ps1 -Game the-binding-of-isaac -ProjectRoot C:/path/to/mod -OutputPath C:/path/to/mod/tools/workshop-release-profile.json -Variant $variants
pwsh ./Test-ModdingToolkitEnvironment.ps1 -ProjectProfile C:/path/to/mod/tools/workshop-release-profile.json
```

## 交给 AI 操作

将下面内容发送给能够读取仓库并运行 PowerShell 7 的编码代理：

> 读取 game-modding-toolkit 根目录、Steam Workshop 能力目录和 The Binding of Isaac 目录中的 AGENTS.md 与 README。先运行环境诊断；缺少配置时使用配置生成器。随后只运行只读预检并汇报 Git SHA、Workshop 身份、候选版本、预览图哈希和证据目录。除非我明确说“发布”，不要传递 -Publish。

完整通用流程及发布提示词见 [`../../docs/ai-integration.md`](../../docs/ai-integration.md)。

## 常见故障

- **找不到上传器**：确认 Steam 库可读取，或使用 `-UploaderPath`。
- **窗口焦点失败**：关闭遮挡上传器的系统级窗口，确保当前桌面允许前台交互。工具每一步都会重新获取窗口，不复用旧句柄。
- **HTTPS 预览失败**：适配器不会让旧 Qt 直接加载 HTTPS，而是先下载远端预览图再通过文件对话框选择。
- **Steam API 超时**：检查代理或网络；上传后超时不会触发第二次上传。
- **候选被上传器改写**：发布结束后重新运行项目构建器；项目工作树若变化，流程会失败并留下证据。
- **残留表单**：关闭旧上传器进程后重新预检；真实发布前应从干净表单开始。
