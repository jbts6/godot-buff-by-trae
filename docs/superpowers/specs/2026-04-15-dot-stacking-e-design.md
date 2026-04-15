# E（DOT 更完整）设计：E1 DOT 叠加策略（按来源合并）

## 目标（本轮最小集）

把 DOT 的“叠加策略”做成可预测、可回归，并满足你的真实需求：

> **同一目标身上的同一种 DOT（同 buff_id），不同来源的伤害要分开计算。**

因此本轮采用：

> **按来源实体合并：同目标 + 同 DOT buff_id + 同 source_entity_id 合并为 1 条 DotInstance；不同 source_entity_id 各自一条。**

并保持性能约束不变：
- tick 只遍历 `dots_by_target[target]`（不遍历全 buff 实例）
- 有专门 GUT 单测覆盖（无单测不算完成）

---

## 背景/动机

你指出的关键点成立：DOT 伤害可能读取“火焰伤害/ATK 等来源属性”，不同角色数值不同，因此“后施加覆盖前施加来源”会非常反直觉。

所以我们需要：
- **不同来源的 DOT 作为不同实例存在**（至少在计算上独立）
- 同一来源重复施加时，才进行合并/叠层/刷新

---

## 新语义：按来源合并（per-source merge）

### 1) 合并键

合并键 = `(target_entity_id, buff_def_id, source_entity_id)`

推论：
- 同目标上，同 DOT buff_id 的 DotInstance 数量最多为“来源数”
- 不同来源互不影响（伤害各读自己的来源属性）

### 2) 同一来源重复施加时的合并规则（你已确认）

#### 2.1 duration 刷新

再次施加时：**直接重置**
```
remaining_turns = turns
```

#### 2.2 强度合并（叠层）

强度使用 DotInstance 的 `stacks` 表示（新增字段），并按 `buff_def.stack` 驱动：

- `stack.mode == "REPLACE"`（或缺省 stack）：
  - `stacks = 1`
- `stack.mode == "ADD_STACK"`：
  - `stacks = min(stacks + 1, max_stack)`
- `stack.mode == "MULTI_INSTANCE"`：
  - 对 DOT：本轮不支持（会与“按来源合并”语义冲突，且容易产生爆量实例）
  - 编译校验：建议直接报错，避免隐式降级导致误用

### 3) 伤害公式

沿用现有最小实现，并引入 stacks：
```
damage = source_stat * base_ratio * stacks
```

其中：
- `source_stat` 由 `read_source_stat` 指定，来自 `source_entity_id` 的 `Stats.get_final`
- `base_ratio` 来自 `buff_def.dot.base_ratio`
- `stacks` 来自 DotInstance

### 4) tick 与生命周期

- tick_phase：仍支持 `TURN_START / TURN_END`
- 每次 tick 后：`remaining_turns -= 1`，到 0 移除 DotInstance
- A4：若 owner buff 实例 inactive，则暂停 tick 且不递减 remaining_turns（保持现有行为）

### 4.1 tick 结算聚合（你新增的关键需求）

对同一次 tick（同 target_entity_id + 同 tick_phase）：

> **对 tags_mask 相同的 DOT，将“各来源分别计算出来的 base_damage”求和，只对目标结算“一段伤害”。**

示例：同一目标上 A 来源 DOT=10，B 来源 DOT=20  
则目标只受到 **一段** 30 的 DOT 伤害（而不是 10、20 两段）。

实现约束与解释：
- “分别计算”仍然存在：每条 DotInstance 仍按其 `source_entity_id` 读取来源属性，得到自己的 `base_damage_i`
- “一段伤害”只影响对目标的 `deal_damage_with_tags` 调用次数（以及 DamageTrace 的条数）
- 为避免不同元素/标签混算，本轮采用你确认的聚合范围：**同 target + 同 tick_phase + 同 tags_mask 才聚合**
  - 不同 tags_mask（例如 FIRE vs POISON）会分开结算为多段（未来做抗性/减免时更安全）
  - 同 buff_id 的 tags_mask 通常相同，因此你的“多来源同类 DOT 合并为一段”自然成立

追帧建议：
- `dot_traces` 仍可按 DotInstance 逐条记录（用于调试“每个来源贡献了多少”）
- 但 `damage_traces`（若有）应体现为“聚合后的一段伤害”

### 5) 清理规则（驱散/移除）

- DotInstance 仍记录 `owner_buff_inst_id`（归属的 buff 实例）
- 当 `remove_by_instance` 移除该 buff 实例时，必须删除对应 DotInstance（已有逻辑）
- 当同一来源重复施加并“命中既有 DotInstance”时：
  - `owner_buff_inst_id` 更新为最新一次施加创建/命中的实例（便于追溯）

---

## 数据层建议（rpg_tests fixtures）

新增测试用 DOT buff（示例）：
- `buff_dot_fire_stack_3t`：`stack.mode=ADD_STACK max_stack=3`，duration turns=3

---

## 单测（必须）

新增 GUT 用例（建议放 `addons/omnibuff/tests/rpg/`）：

1) `test_dot_merge_by_source_produces_two_instances.gd`
- 同一目标分别由 source=3001 与 source=3002 施加同一个 DOT buff_id
- 断言：`dots_by_target[target].size() == 2`
- 并验证 tick 产生 2 条 dot_traces（与现有 `test_dot_multi_source_trace.gd` 语义一致）
- 以及验证：对目标的伤害结算为 1 段（两来源的 base_damage 被聚合）

2) `test_dot_merge_by_source_refresh_and_stack.gd`
- 同一来源对同一目标重复施加 DOT（ADD_STACK）
- 断言：DotInstance 数量仍为 1
- 断言：stacks 增加，且 tick 伤害随 stacks 增大
- 断言：再次施加后 `remaining_turns` 被重置为 turns（不会提前到期）

---

## 验收标准

- 按来源合并语义落地
- 新增单测全绿
- 现有 `res://addons/omnibuff/tests/test_dot_multi_source_trace.gd` 保持通过（它正好验证“不同来源两条 trace”）
- “多来源同 tags_mask 的 DOT 对目标只造成一段伤害”的单测通过
