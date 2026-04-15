# OmniBuff A4（WHILE_CONDITION）设计：路线 A（挂起/恢复）

## 目标

为 Buff 系统补齐 A4：**条件型持续（WHILE_CONDITION）** 的最小可行版本，并确保：

- Buff 实例在条件不满足时 **不被删除**，而是进入 `inactive`（挂起）状态；
- 条件再次满足时可 **恢复激活**，并保留其生命周期信息（stacks、remaining_turns、source、ownership 等）；
- 对已实现体系的兼容：不破坏 A1（叠加）/A2（刷新策略）/A3（到期）/DOT TURN_START 等现有语义与测试。

本阶段重点：**先验证最小可行性**，随后再扩展更多条件来源与场景。

---

## 范围（v1）

### 支持

1) **条件类型：基于属性阈值（STAT_THRESHOLD）**

- 以目标实体 `StatsComponent.get_final(stat_id)` 的结果为准（即最终值，含 modifiers）
- 支持比较符：
  - `LE`（<=）
  - `LT`（<）
  - `GE`（>=）
  - `GT`（>）

2) **挂起/恢复（路线 A）**

- `inactive`：撤销该实例注入的 modifiers、注销事件监听（EventIndex listener），DOT 将被“暂停 tick”（见下文）
- `active`：按当前 stacks 重建 modifiers、重新注册事件监听；DOT 恢复 tick

3) **评估时机（最小实现）**

- 在 `BuffCore.on_turn_start` 与 `BuffCore.on_turn_end` 的 tick 中，对“带条件的 buff 实例”进行条件评估与状态切换
- 在 `apply_buff` 创建实例后立即进行一次评估（决定初始 active/inactive）

> v1 不做“任意时刻属性变化立即评估”（事件驱动的即时刷新），以保证实现最小且可预测；回合制中通过 turn tick 已足够覆盖大多数场景（HP 变化、DOT 变化等）。

### 不支持（v1）

- 多条件组合（AND/OR），v1 仅支持单条条件；若配置多个条件，按 AND 全部满足才激活（最小且直观）
- 复杂条件源（装备/套装计数、目标身上是否存在某 buff、阵营、距离等）
- 条件变化立即触发（非 turn tick）

---

## 数据协议（buff_defs.json）

在 buff_def 中新增（已存在字段 `conditions`，v1 开始赋予明确语义）：

```json
"conditions": [
  {
    "condition_type": "STAT_THRESHOLD",
    "stat": "HP",
    "op": "LE",
    "value": 50
  }
]
```

字段说明：
- `condition_type`: 仅支持 `"STAT_THRESHOLD"`
- `stat`: stat id（字符串），例如 `"HP"`、`"ATK"`
- `op`: `LE/LT/GE/GT`
- `value`: 数值阈值（float）

> v1 使用“绝对阈值”，例如 HP<=50。后续可扩展 percent（HP<=0.5*HP_MAX）等。

---

## 运行时模型与语义

### 1) BuffInst 新增字段

在 `BuffCore.BuffInst` 增加：
- `active: bool = true`：实例是否处于激活状态
- （可选）`has_conditions: bool`：加速判断（也可运行时从 buff_def.conditions 判空判断）

### 2) 激活/挂起对系统的影响

#### (1) modifiers（StatsCore）

- active → 注入 modifiers（按 stacks 缩放，沿用 A1 的线性策略）
- inactive → 撤销该实例的 modifiers（按 source_inst_id 清理）

#### (2) triggers（EventIndex）

- active → 注册 listeners，并记录到 `listener_ids_by_inst[inst_id]`
- inactive → 注销 listeners（复用现有 `_unregister_listeners_for_inst(inst_id)`）

#### (3) DOT（DotInstance）

v1 采用**最小改动且不丢状态**的“暂停”方式：

- DotInstance 仍保留在 `dots_by_target` 中（因此 remaining_turns 不丢失）
- 在 `_tick_dots` 处理某个 dot 前：
  - 通过 `owner_buff_inst_id` 找到对应 BuffInst
  - 若 BuffInst 不存在或 `active=false` → **跳过该 dot**（不结算、不递减 remaining_turns）

这样即可实现“条件失效时暂停 DOT，条件恢复时继续”。

> 注意：驱散/到期/主动移除仍会真正删除 DOT（remove_by_instance 已实现清理）。

### 3) 条件评估函数

新增内部函数：
- `_conditions_satisfied(stats: OmniStatsComponent, buff_def: Dictionary) -> bool`

规则：
- 若 `conditions` 为空：返回 true（与现有行为一致）
- 若存在多条条件：全部满足才返回 true（AND）
- 不识别的 condition_type/op：返回 true 或 false？
  - v1 建议 **返回 true 并 push_warning**（避免旧数据因未知字段突然失效）
  - 但对测试数据/strict 模式，后续可在 validators 中升级为 error

### 4) 状态切换

新增内部函数：
- `_set_instance_active(stats, inst_id, want_active)`
  - want_active=true 且当前 inactive → `_activate_instance(...)`
  - want_active=false 且当前 active → `_deactivate_instance(...)`

并在 turn tick 中调用：
- `_evaluate_condition_transitions(stats_by_entity)`
  - 遍历 `inst_ids.duplicate()`
  - 对每个 inst，根据条件计算 want_active
  - 执行状态切换

### 5) 与 A1/A2/A3 的交互约定

- **A1 叠加**：对 inactive 实例执行 ADD_STACK/REPLACE 时，仍按规则更新 stacks/remaining_turns（以及 refresh_policy）；是否生效取决于条件评估（下一次 tick 或 apply 后立即评估）。
- **A2 刷新策略**：refresh_policy 只影响 remaining_turns，不直接改变 active；当条件满足时实例恢复激活，effects 将按最新 stacks 生效。
- **A3 到期**：到期递减仅在 inst.active=true 时推进，还是 inst.active=false 也推进？
  - v1 建议：**active/inactive 都推进 remaining_turns**（因为“挂起”是效果不生效，不应变成永久 buff）
  - 但 DOT 的 remaining_turns 在 inactive 时暂停（因为它代表“DOT 跳数”）
  - 即：非 DOT 的 TURNS 仍随回合流逝到期；DOT 在挂起时暂停跳数。

---

## 测试策略（GUT）

新增一个最小可行的条件 buff（放入 `data/rpg_tests/buff_defs.json`）：

`buff_cond_hp_le_50_atk_up_10`
- conditions: HP <= 50 时激活
- effects: ATK +10（ADD/FLAT）
- duration: PERMANENT 或 TURNS（v1 推荐 PERMANENT，先聚焦条件切换）

测试用例（新建 `tests/rpg/test_buff_lifecycle_while_condition.gd`）：

1. 初始 HP=100：施加 buff 后应处于 inactive（ATK 不变）
2. 扣血到 50：在下一次 `on_turn_start`（或 `on_turn_end`）评估后变 active（ATK +10）
3. 回血到 60：下一次 tick 后变 inactive（ATK 回退）

（可选）补充到期交互测试：
- duration.type=TURNS turns=2，条件一开始不满足（inactive）
- 连续推进回合到期后应移除实例（证明 inactive 不会“无限挂着”）

---

## 验收标准（A4 v1）

- A4 最小条件可用：STAT_THRESHOLD + 挂起/恢复
- modifiers 与 triggers 在 active/inactive 切换时正确注入/撤销
- DOT 在 inactive 时不会 tick，恢复后继续 tick（不丢 remaining_turns）
- GUT 新增用例通过，且现有测试不回归

