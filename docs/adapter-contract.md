# Steam Workshop 适配器契约

通用编排器负责配置验证、Git、Steam 只读检查、预览图保护、状态机和“上传至多一次”。游戏适配器只负责上传器边界。

## 必需函数

- `Open-GMTWorkshopUploader -Configuration -EvidenceRoot`：打开或恢复上传器，返回会话；失败不得留下伪成功会话。
- `Open-GMTWorkshopProject -Session -Item -EvidenceRoot`：加载一个已验证变体，不触发上传。
- `Invoke-GMTWorkshopUploadOnce -Session -Item -EvidenceRoot`：唯一允许触发 Upload 的函数；同一会话重复调用必须失败。
- `Close-GMTWorkshopUploader -Session`：尽力关闭本工具打开或接管的上传器，不掩盖原始异常。

可选函数 `Test-GMTWorkshopAdapterEnvironment -Configuration` 只进行环境发现，返回事实对象；不得启动上传器、改变窗口、写文件或访问远端。

适配器必须把可预期的外部失败作为明确异常暴露，不能自动重复提交、静默切换项目或猜测窗口。新适配器应复制游戏目录中的 `_template`，并运行与假适配器相同的共享契约测试。
