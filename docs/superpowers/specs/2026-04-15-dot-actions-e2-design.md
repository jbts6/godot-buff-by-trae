# E2（DOT 更完整）设计：DOT stacks 操作 actions

## 目标（本轮最小集）

提供一组事件 action，用于**直接操纵目标身上的 DOT 实例（DotInstance）**：

- 翻倍层数（MUL）
- 加/减层数（ADD，支持负数）
- 设定层数（SET）
- 清除 DOT（CLEAR）

并满足你在 E1 已确立的 DOT 体系：
- DOT 按来源合并（同 target+buff_id+source 1 条 DotInstance）
- tick 结算按 tags_mask 聚合（同 tags_mask 结算为 1 段伤害，不同 tags_mask 分段）

同时保证：
- 不遍历全 buff，只遍历目标的 `dots_by_target[target]`
- 不破坏现有“驱散”语义与相关单测
- 有专门 GUT 单测覆盖（无单测不算完成）

---

## 新增 action_kind

在 `enums.action_kind` 增加：
- `DOT_MUL_STACKS`
- `DOT_ADD_STACKS`
- `DOT_SET_STACKS`
- `DOT_CLEAR`

---

## Action 数据协议（trigger.action）

通用字段：
- `kind`: 上述 action_kind
- `scope`: 使用 trigger 的 scope（`TARGET/SELF/SOURCE`），决定“对谁的 DOT 生效”

### 1) 选择哪些 DOT（筛选器）

action 支持以下筛选字段（你已确认）：

- `dot_buff_id: String`（精确匹配 DOT buff_id）
- `dot_tags_mask_any: Array[String]`（按 tag 过滤：任意命中即匹配）

匹配规则：
- 若两者都提供：必须同时满足
- 若两者都未提供：该 action 视为 no-op（避免误操作“清空全体 DOT”）

### 2) stacks 操作参数

- `DOT_MUL_STACKS`: `value` 视为 multiplier（int，>=0）
- `DOT_ADD_STACKS`: `value` 视为 delta（int，可为负）
- `DOT_SET_STACKS`: `value` 视为新 stacks（int，可为负；<=0 等价 CLEAR）
- `DOT_CLEAR`: 不需要 value（忽略 value）

### 3) stacks 边界

对每个命中的 DotInstance：
- 操作后若 `stacks <= 0`：移除 DotInstance
- 若对应 dot buff 的 `stack.max_stack` 存在：`stacks = min(stacks, max_stack)`

---

## 关键语义：操作后刷新 duration（你已确认）

对每个“未被移除”的 DotInstance：
- 将 `remaining_turns` 直接重置为其 buff_def.duration.turns

解释：玩家感知上，“翻倍/加层/设层”等价于“添加了同等效果的 DOT”，所以应刷新持续时间。

---

## 与驱散/移除的关系（必须保持不破坏）

本轮动作只修改 `DotInstance`（`stacks/remaining_turns` 或删除实例）：
- **不删除 buff 实例**（inst_ids/instances_by_id），避免破坏 A/B 的“实例级”语义
- 驱散/主动移除仍按现有 `remove_by_instance` 清理 DotInstance（通过 `owner_buff_inst_id`）
- 这意味着：E2 的 CLEAR 可能导致“buff 实例仍存在但不再 tick DOT”，这是允许的（数据语义：DOT伤害已被清除）

---

## 单测（必须）

新增 GUT 测试（建议放 `addons/omnibuff/tests/rpg/`）：

1) `test_dot_action_mul_add_set_clear.gd`
- 给目标先施加 `buff_dot_fire_stack_3t`（stacks=1）
- 给攻击者挂一个触发 buff（AFTER_DEAL / 或 APPLY 阶段）执行：
  - MUL：stacks 翻倍（并刷新 turns）
  - ADD：delta=-1 使 stacks 变 0 并清除
  - SET：stacks=3（并刷新 turns，且 cap 到 max_stack）
  - CLEAR：直接移除 DotInstance

2) `test_dot_action_filter_by_tags_mask_any.gd`
- 同时存在 FIRE 与 POISON 的 DOT（tags_mask 不同）
- 执行 `dot_tags_mask_any=["POISON"]` 的操作只影响 POISON，不影响 FIRE

并保证：
- 现有 dispel/immune 相关测试仍通过

