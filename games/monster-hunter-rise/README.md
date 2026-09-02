# Monster Hunter Rise

本目录提供《怪物猎人：崛起：曙光》的可复用 Mod 能力。首个能力是数据驱动的[武器攻击特效运行时](capabilities/weapon-vfx/README.md)。

它将武器项目拆成两部分：

- 通用代码：动作状态机、空击/命中派发、持续实例生命周期、命中鉴权适配和运行报告。
- 项目数据：武器身份、动作配方、Effect ID、资源闭包和视觉验收标准。

当前参考实现面向 Steam 版 16.0.2.0、REFramework 与 yun_modules。其他版本必须重新验证类型数据库、动作和命中契约，不能只修改版本字符串。
