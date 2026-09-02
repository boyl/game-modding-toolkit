# 武器攻击特效运行时

该能力用于创建只改变本地视觉的《怪物猎人：崛起》武器攻击特效 Mod。采用单向依赖：

```text
武器 Profile 与动作配方
        ↓
WeaponVfxRuntime 通用状态机
        ↓
游戏运行时适配器
        ↓
REFramework / yun_modules / 游戏接口
```

不采用 MVC：这里没有界面或用户交互状态；数据驱动管线更容易隔离武器差异并执行契约测试。

## 可复用边界

- `runtime/WeaponVfxRuntime.lua`：武器无关的动作、空击、命中、次数限制和实例释放逻辑。
- `schemas/weapon-vfx-profile.schema.json`：武器身份、动作银行、Provider Container、生命周期与动作配方契约。
- `Test-WeaponVfxProfile.ps1`：离线 Schema 和跨字段生命周期检查。
- `New-WeaponVfxProject.ps1`：从已验证 Profile 生成只含配置与引导文件的项目骨架。

运行时通过适配器注入游戏接口。适配器必须实现：

- `register_update(callback)`、`register_hit(callback)`、`register_reset(callback)`；
- `get_action_context()`；
- `authorize_hit(raw_hit, profile)`；
- `effect_exists(container_id, effect_id)`；
- `dispatch_effect(container_id, effect_id, sync)`；
- `create_effect_instance(container_id, effect_id, sync)`；
- `release_effect_instance(instance)`。

`sync` 始终由引擎传入 `false`。适配器不得擅自改为网络派发。

## 新武器最小流程

1. 复制示例 Profile，填写武器类型、动作银行、Container 和至少三条 MVP 动作。
2. 运行 `Test-WeaponVfxProfile.ps1`，先消除结构与生命周期错误。
3. 建立该版本的 REFramework 适配器并验证精确命中来源。
4. 分别验收空击、命中和持续效果释放；计数与实际画面必须同时通过。
5. 视觉方向确认后再扩充完整动作表和资源闭包。

项目素材、动作表和游戏资源不得提交到本工具仓库。
