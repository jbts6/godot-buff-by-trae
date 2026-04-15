因此同一目标上，同一 DOT buff_id 的 DotInstance 数量最多为 1。

### 2) 再次施加时的合并规则（两件事）

#### 2.1 duration 刷新（你已确认）

再次施加时：**直接重置**
```
remaining_turns = turns
```

#### 2.2 强度合并（沿用 stack.mode）

强度使用 DotInstance 的 `stacks` 表示（新增字段），并按 buff_def.stack 驱动：

- `stack.mode == "REPLACE"`：
  - `stacks = 1`
- `stack.mode == "ADD_STACK"`：
  - `stacks = min(stacks + 1, max_stack)`
- `stack.mode == "MULTI_INSTANCE"`：
  - 对 DOT：本轮不再允许（否则与“全局合并”冲突）
  - 编译校验：若 DOT buff 声明 MULTI_INSTANCE，则报错或强制降级为 REPLACE（推荐：报错，避免隐式语义）

> 注：如果 dot buff 缺失 stack，则默认视为 REPLACE（stacks=1）。

### 3) 来源实体（source_entity_id）处理

由于全局只有 1 条实例，必须确定“来源是谁”。

规则：**采用最后施加者覆盖**
- 每次合并时，将 DotInstance.source_entity_id 更新为本次施加者 `source_entity_id`

动机：
- 符合“后施加覆盖前施加”的直觉与可解释性
- 让 DOT 动态读取的来源属性（ATK等）能反映“最新来源”

### 4) 伤害公式

沿用现有最小实现，并引入 stacks：
```
damage = source_stat * base_ratio * stacks
```

其中：
- `source_stat` 由 `read_source_stat` 指定，来自 `source_entity_id` 的 `Stats.get_final`
- `base_ratio` 来自 `buff_def.dot.base_ratio`
- `stacks` 来自 DotInstance

### 5) tick 与生命周期

- tick_phase：仍支持 TURN_START / TURN_END
- 每次 tick 后：`remaining_turns -= 1`，到 0 移除 DotInstance
- A4：若 owner buff 实例 inactive，则暂停 tick 且不递减 remaining_turns（保持现有行为）

### 6) 清理规则（驱散/移除）

- DotInstance 仍记录 `owner_buff_inst_id`（归属的 buff 实例）
- 当 `remove_by_instance` 移除该 buff 实例时，必须删除对应 DotInstance（已有逻辑）
- 因为现在 DotInstance 被合并，需确保 “同 buff_id 多次施加时 owner_buff_inst_id 的更新策略”一致：
  - 推荐：owner_buff_inst_id 更新为最新一次施加时创建/命中的实例（便于追溯最新来源）

---

## 数据层建议（rpg_tests fixtures）

新增测试用 DOT buff（示例）：
- `buff_dot_fire_stack_3t`：`stack.mode=ADD_STACK max_stack=3`，duration turns=3

以及一个触发 buff（或直接在测试里重复 apply_buff）用来构造：
- 同回合多次施加同一个 DOT buff_id

---

## 单测（必须）

新增 GUT 用例（建议放 `addons/omnibuff/tests/rpg/`）：

1) `test_dot_global_merge_single_instance.gd`
- 对同一目标连续 apply 同一个 DOT buff_id 3 次
- 断言：`dots_by_target[target].size() == 1`

2) `test_dot_global_merge_refresh_and_stack.gd`
- 对同一目标 apply DOT（ADD_STACK）两次
- 断言：stacks 增加，tick 伤害随 stacks 增大
- 断言：再次施加后 `remaining_turns` 重置为 turns（可通过 tick 若干回合验证不会过早结束）

---

## 验收标准

- 新增 DOT 全局合并语义落地
- 上述单测全绿
- 现有 DOT 多来源追帧测试若依赖“多实例”行为，需要：
  - 更新为验证“source 被覆盖为最后施加者”或
  - 迁移到“按来源合并”分支（不在本轮）

