# OmniBuff 生命周期（A1+A3）设计：叠加 + 到期

## 目标

在当前版本基础上，把 “Definition of Done” 中 **A. 核心正确性（Buff 生命周期）** 的第一档做实：

- **A1 叠加策略完整（最小集）**：`REPLACE / ADD_STACK / MULTI_INSTANCE` + `max_stack` + `ownership_mode`
- **A3 到期/持续完整（非 DOT）**：`duration.type=TURNS` 的普通 buff 会随回合推进递减并到期移除；`duration.tick_phase` 支持 `TURN_START / TURN_END`

同时用 GUT 新增生命周期测试，保证可回归。

---

## 约束与现状

### 硬约束（保持不变）
- 伤害热路径仍需遵守：
  - 属性读取只经 `StatsComponent.get_final()`（StatCache）
  - 事件触发只遍历 `EventIndex.listeners[key]` 子集

### 当前实现缺口
- `BuffCore.apply_buff()` 目前每次都会创建新实例，未实现 stack.mode/ownership_mode/max_stack
- `BuffInst.remaining_turns` 目前不递减、也不自动到期移除（非 DOT）

---

## 数据协议（已存在字段，本次开始落地）

buff_def（示例）：

```json
"duration": { "type": "TURNS", "turns": 3, "tick_phase": "TURN_END" },
"stack": { "mode": "ADD_STACK", "max_stack": 5, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "GLOBAL" }
```

本次落地字段：
- `duration.type=TURNS`
- `duration.turns`
- `duration.tick_phase`：`TURN_START` 或 `TURN_END`
- `stack.mode`：`REPLACE | ADD_STACK | MULTI_INSTANCE`
- `stack.max_stack`
- `stack.ownership_mode`：本次只定义两种最常用语义
  - `GLOBAL`：全局唯一（同 buff_id 只有一个“归属实例”）
  - `BY_SOURCE_INSTANCE`：按来源实体分开（同 buff_id 可按 source_entity_id 各有一个归属实例）

> 注：`refresh_policy` 此阶段不做完整实现，但需要一个最小且可预测的语义（见下文）。

---

## 运行时语义设计

### 1) 叠加 key（ownership key）

对“可聚合/可替换”的模式（REPLACE/ADD_STACK），需要先找到目标实例：

`ownership_key = (buff_def_id, owner_key)`

- 若 `ownership_mode == GLOBAL`：`owner_key = 0`
- 若 `ownership_mode == BY_SOURCE_INSTANCE`：`owner_key = source_entity_id`

MULTI_INSTANCE 模式不查找旧实例（每次施加都创建新实例）。

### 2) REPLACE

- 若存在同 ownership_key 的实例：
  - 移除旧实例（撤销 modifiers、注销事件、清理 DOT 实例）
  - 创建新实例（stacks=1，remaining_turns=turns）
- 若不存在：直接创建

### 3) ADD_STACK

- 若不存在同 ownership_key 实例：创建新实例（stacks=1）
- 若存在：`stacks = min(stacks + 1, max_stack)`
- **最小刷新语义（本阶段约定）**：当命中已有实例（即叠加成功）时，将该实例 `remaining_turns` 重置为配置 `turns`
  - 这相当于 `refresh_policy=RESET_TO_MAX` 的最常见行为，但不依赖 refresh_policy 字段

对属性型 effects：
- 叠加后必须让数值随 stacks 生效（最小实现：把该实例的 modifier value 乘以 stacks，或在重建 modifiers 时按 stacks 注入）。

### 4) MULTI_INSTANCE

每次施加都创建一个 BuffInst：
- stacks 固定为 1
- remaining_turns 初始化为 turns

### 5) 普通 buff 的 TURNS 到期

在 `BuffCore.on_turn_start / on_turn_end` 中增加“非 DOT buff 的到期推进”：

- 仅处理 `duration.type == "TURNS"` 且 `turns > 0`
- 仅在 `duration.tick_phase == 当前阶段` 时递减 `remaining_turns -= 1`
- `remaining_turns <= 0` 时移除该实例（走统一 `remove_by_instance`）

> DOT 的 remaining_turns 仍由 DOT tick 逻辑管理（已实现 TURN_START/TURN_END）。

---

## 测试策略（GUT）

### 测试数据
使用 `data/rpg_tests/` 数据集新增一组仅用于生命周期的 buff（不污染 base_demo）。

### 新增测试用例（核心断言）

1. **REPLACE（GLOBAL）**
   - 同 buff_id 连续施加两次（来源不同也应替换）
   - 断言：实例数为 1、数值为单份效果、remaining_turns 被重置

2. **ADD_STACK（GLOBAL）**
   - 连续施加 N 次，断言 stacks 增长且不超过 max_stack
   - 断言：数值随 stacks 线性增长（flat add）
   - 断言：叠加时 remaining_turns 重置

3. **MULTI_INSTANCE**
   - 连续施加 3 次，断言实例数为 3，数值为 3 份叠加

4. **TURNS 到期（非 DOT）**
   - 创建 `turns=2` 的 buff，按 tick_phase 调用 TurnStart/TurnEnd
   - 断言：第一次 tick 后仍存在；第二次 tick 后被移除；数值回到无 buff 状态

---

## 非目标（本阶段不做）

- 不实现完整 `refresh_policy` 矩阵（NONE/EXTEND/…）
- 不实现 `WHILE_CONDITION`（A4）
- 不实现更完整的 phase/priority（C3/C5 的完整版本）

---

## 验收标准

- 新增生命周期用例在 GUT 下全绿
- `apply_buff` 行为与 stack.mode/ownership_mode/max_stack 对齐
- 非 DOT 的 `TURNS` buff 可在 tick_phase 指定阶段到期移除
- 对既有测试无破坏（尤其是伤害/事件/DOT/驱散/免疫相关测试）

