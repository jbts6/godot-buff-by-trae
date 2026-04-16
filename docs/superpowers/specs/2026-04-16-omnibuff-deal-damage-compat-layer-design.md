# OmniBuff：deal_damage 兼容层（API 稳定性）设计

## 背景

近期我们对 `OmniDamagePipeline.deal_damage()` 增加了新参数：
- `is_bonus_damage: bool = false`

这会在部分场景引入“旧调用不兼容”的风险：
- 旧项目可能通过 **位置参数** 调用 `deal_damage(...)`，且调用点不受控
- 插件升级后若函数签名变更，GDScript 编译可能直接报错

同时，我们希望“稳定 API”提供更推荐的调用方式：
- 引导外部使用命名参数（或 wrapper），减少未来再次变更的成本

---

## 目标

1) **不破坏旧项目**：旧调用（不带 is_bonus_damage）仍可用
2) **提供稳定入口**：在 `OmniBuff` singleton 中提供 `Damage` 兼容 wrapper，作为未来对外 API 的推荐入口
3) **减少未来变更影响**：外部只依赖 wrapper 的“稳定签名”，内部函数可继续演进

---

## 方案选型

### 方案 A（推荐）：新增 wrapper 方法，不再改动原签名

在 `damage_pipeline.gd` 中：
- 保持 `deal_damage(...)` 的“当前签名”为内部实现（可以继续演进）
- 新增 `deal_damage_v1(...)`（稳定签名，**不含 is_bonus_damage**）内部调用 `deal_damage(..., is_bonus_damage=false)`

在 `omnibuff_singleton.gd` 中：
- 暴露 `DamagePipeline` 之外，再暴露一个 `DamageCompat`（或直接暴露 `DamagePipeline.deal_damage_v1` 的用法）
- 推荐接入方使用 `OmniBuff.DamagePipeline.new().deal_damage_v1(...)` 或 `OmniBuff.damage_deal_v1(...)`

优点：
- 最稳：旧调用改为调用 v1，可逐步迁移
- 未来升级：可继续加 v2/v3

缺点：
- 多一个方法名（但清晰）

### 方案 B：用可选参数维持单一签名

维持当前已加的 `is_bonus_damage` 可选参数，理论上旧调用不受影响。

缺点：
- 外部如果用了“位置参数 + 自己封装”，未来再加参数仍可能破

结论：采用 A（推荐），并保留 B 的现状；即 **新增稳定 wrapper**。

---

## API 约定

### damage_pipeline.gd

- `deal_damage_v1(attacker, defender, buff_attacker, buff_defender, ds, base_damage, replay, turn_index, tags_mask, runtime, roll_key, skill_id, damage_type, element)`
  - 与旧版一致（不含 is_bonus_damage）
  - 内部转调 `deal_damage(..., is_bonus_damage=false)`

（可选）再提供：
- `deal_damage_bonus(...)`：固定 `is_bonus_damage=true`（供事件动作调用；但不是对外稳定 API）

### omnibuff_singleton.gd

新增暴露：
- `DamagePipeline`（已存在）
- `DamagePipelineV1`（指向同一 script，文档上强调使用 `deal_damage_v1`）
- 或提供函数 `damage_deal_v1(...)`（更“命名空间式”）

---

## 测试策略

新增一个轻量 test：
- 直接调用 `OmniDamagePipeline.new().deal_damage_v1(...)` 确保可运行
- 与 `deal_damage(..., is_bonus_damage=false)` 行为一致（至少能返回 ctx，不崩）

---

## 验收标准

- [ ] 新增 wrapper 方法 `deal_damage_v1` 并能通过编译
- [ ] 新增测试覆盖 wrapper
- [ ] singleton 注释/导出更新，指导使用方走稳定入口

