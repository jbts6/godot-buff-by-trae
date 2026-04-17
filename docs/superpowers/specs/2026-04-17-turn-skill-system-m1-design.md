# turn_skill_system M1 设计规格（Spec）

**目标迭代：M1（结算闭环 + 稳定性）**  
**范围选择：新文件（不修改现有 `docs/turn_skill_system/turn_skill_system_spec.md`）**  
**开发规约：严格 TDD（双提交：RED→GREEN） + GUT**  

## 0. 背景与现状

当前 `turn_skill_system` 已具备：
- JSON 权威技能数据：active/passive/aura
- `SkillDB`：index + lazy load + cache
- `SkillRuntime`：`cast/cast_to_unit/cast_to_cell/simulate_cast`
- `TargetingRegistry`（FIRST/ALL/single_cell/cross）
- `EffectRegistry`（damage/apply_buff/remove_buff/heal）
- `BattleEventBus`（事件捕获 + 统一派发）
- `OmniBuffAdapter`：damage 走 `DamagePipeline.deal_damage`（兜底 `deal_damage_v1`），buff 走 `BuffCore`
- 基础 demo + Editor Dock + GUT tests

但 M1 需要补齐的关键点是：**结算闭环的“可依赖性”**（特别是 heal 的真实落地、错误分支与返回结构稳定、DamagePipeline 参数透传与一致性、回放/追溯可用）。

---

## 1. M1 的目标（Goal）

在不改变现有外部 API（`SkillRuntime.*`）的前提下，实现：
1) **Heal 正式落地**（非仅事件）：与 OmniBuff 生态一致、可回放、可被 buff 影响。  
2) **cast 返回结构稳定化**：所有成功/失败路径都返回稳定字段；errors/issues/events/effects 具有固定语义。  
3) **DamagePipeline 参数透传与一致性**：damage_type/element/tags_mask/is_bonus_damage/skill_id_int/roll_key/turn_index 能正确进入 pipeline；并能在 tests 中断言。  
4) **失败/边界用例补齐**：技能缺失、类型不匹配、无目标、缺少 omnibuff context、targeting 缺 primary_cell 等，都有清晰错误码。  
5) **测试优先**：所有新增行为必须先有 RED 测试，再有 GREEN 实现；并且新增测试应能在 CI/headless 下稳定运行。

---

## 2. 非目标（Non-Goals）

以下不在 M1 中做（后续 M2/M3 再做）：
- 新增大量 targeting 规则、复杂 AoE 几何
- 新增大量 effect kind（shield/dispel/move 等）
- 复杂 passive/aura 规则体系（冷却、叠层策略、动态范围）
- Editor Dock 的结构化表单编辑器（M3）

---

## 3. 设计约束（Constraints）

### 3.1 兼容性与稳定性
- **不更名** `SkillRuntime.cast/cast_to_unit/cast_to_cell/simulate_cast`
- 尽量避免使用 `:=`（Godot 4 静态分析在动态对象/Variant 上易报解析期错误）
- 所有“字段存在性判断”不得使用不存在的 `has_property()`；统一使用 `get_property_list()` 或 `get()`。

### 3.2 OmniBuff 集成约束
- **damage 必须走** `OmniBuff.DamagePipeline`（优先 `deal_damage`，兜底 `deal_damage_v1`）
- **buff 必须走** `OmniBuff.BuffCore`（apply/remove）
- heal 的落地也必须遵循“可回放/可追溯”的口径（见 4.1）。

### 3.3 Unit 契约（已确认）
Unit 必须提供字段：
`entity_id/camp/cell/stats/buffs`

---

## 4. 关键设计：M1 要补的行为

### 4.1 Heal 的落地（必须）

#### 4.1.1 需求
- `heal` effect 在 `simulation=false` 时必须改变目标的 HP（或等价的生命值属性）。
- heal 需要能够被 buff/被动影响（与 damage 一致的“管线化”思想）。
- heal 必须产生事件（before/after_heal），并在 `cast()` 返回 `events[]` 捕获到。

#### 4.1.2 推荐实现方案（M1 方案）
新增 `OmniBuffAdapter.heal(...)`，优先调用 omnibuff 内若已存在的 **治疗管线**（若当前 omnibuff 未提供，则 M1 内以“最小一致性实现”补一个 `heal_v1`）：
- 输入：attacker_stats/defender_stats/buffs/ds/replay/runtime_dict/turn_index/roll_key/skill_id_int/tags_mask/element 等
- 输出：`{ok, final_heal, meta}`

> 注：M1 不要求 heal 与 damage 在同一类 pipeline 中实现，但要求具备同等“可回放与参数透传”的能力。

#### 4.1.3 JSON 语义
保持现有：
```json
{"kind":"heal","params":{"amount": 10}}
{"kind":"heal","params":{"amount_expr":"10 + a.ATK*0.2","rounding":"floor"}}
```

### 4.2 cast 返回结构稳定化（必须）

#### 4.2.1 固定字段
无论成功/失败，都必须返回这些字段：
- `ok: bool`
- `simulation: bool`
- `skill_id: String`
- `caster_id: int`
- `targets: Array`（失败时为空数组）
- `effects: Array`（失败时为空数组）
- `events: Array`（失败时也应返回已捕获到的 events，至少包含 cast_started）
- `resolved_formulas: Array`
- `rng_seed: int`
- `errors: Array[String]`（失败时必须有至少 1 个错误码）
- `issues: Array`（validator 产生的结构化 issues；成功时可为空）
- `predicted_deltas: Array`（仅 simulation=true 时）

#### 4.2.2 错误码（M1 最小集合）
约定 errors 中使用稳定字符串（便于前端/AI 分支逻辑）：
- `unknown_skill_id:<id>`
- `skill_validation_failed:<id>`
- `skill_type_not_active`
- `no_valid_targets`
- `missing_omnibuff_context(dataset/enums_rt/runtime_dict)`
- `primary_cell_out_of_range`
- `primary_target_is_null`

### 4.3 DamagePipeline 参数透传（必须）

#### 4.3.1 透传字段
`SkillRuntime` 构造 ctx 时必须把以下字段正确传入 adapter：
- `turn_index: int`
- `roll_key: int`
- `tags: Array[String]` → `tags_mask: int`（通过 `enums_rt.tag_mask`）
- `damage_type: (String|int)` → `int`（通过 `enums_rt.enum_int("damage_type", ...)`）
- `element: (String|int)` → `int`（通过 `enums_rt.enum_int("element", ...)`）
- `is_bonus_damage: bool`（可选，默认 false）
- `skill_id_int: int`（可选，默认 -1）

#### 4.3.2 可断言性
`OmniBuffAdapter.deal_damage` 返回 meta 里应包含最小可追溯字段（例如 used=deal_damage/deal_damage_v1、输入参数摘要），用于 tests 断言“确实走了 pipeline 且参数已映射”。

---

## 5. 测试策略（M1）

### 5.1 测试框架
- 使用 GUT：`extends GutTest`
- 通过 `./run_gut_tests.sh` headless 运行

### 5.2 TDD 双提交规则
每个行为点必须拆成两个 commit：
- `test(turn_skill_system): ... (red)`：只改 tests，且能复现失败（断言失败）
- `feat|fix(turn_skill_system): ... (green)`：最小实现让该测试转绿

### 5.3 需要新增/强化的测试用例（M1 列表）
1) **heal 落地**：HP 发生变化 + 捕获 before/after_heal event
2) **cast 失败分支结构稳定**：每个错误码路径都断言返回字段完整且错误码正确
3) **DamagePipeline 参数映射**：传入字符串 damage_type/element/tags，断言 adapter 内部映射结果被使用（通过 meta 或可观测输出）
4) **simulate_cast 不要求 omnibuff context**：simulation=true 时缺少 dataset 仍可运行并产生 predicted_deltas

---

## 6. 交付物（Deliverables）

M1 完成后应交付：
- `heal` 的真实落地（omnibuff adapter 层）
- `SkillRuntime` 返回结构与错误码稳定化
- 新增/完善 GUT tests 覆盖 M1 行为
- `run_gut_tests.sh` 仍可一键跑通全量 tests

