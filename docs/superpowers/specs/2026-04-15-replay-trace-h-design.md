# H（回放与追帧 Replay/Trace）设计（最小收尾）

## 目标（本轮最小集）

把 checklist 的 H1~H3 收尾到可打勾，且不改战斗逻辑：

- **H1 DamageTrace 完整**：字段齐全并有测试锁死
- **H2 DotTrace 完整**：字段齐全并有测试锁死
- **H3 Debug dump 可读**：range dump 输出稳定、便于排障，并有测试锁死

> 现状里 `OmniReplay` 已基本具备这些能力，本轮以“补测试 + 明确契约”为主，避免回归。

---

## 现状（代码）

文件：`addons/omnibuff/runtime/core/replay.gd`

### 已有结构

`OmniReplay` 内已有：
- `damage_traces: Array[DamageTrace]`
- `dot_traces: Array[DotTrace]`

`DamageTrace` 字段（已满足 H1）：
- `turn`
- `attacker_id / defender_id`
- `hit / crit`
- `base_damage / final_damage`
- `tags_mask`
- `triggered_inst_ids`
- `stage_triggers`

`DotTrace` 字段（已满足 H2）：
- `turn`
- `source_entity_id / target_entity_id`
- `read_source_stat / source_stat_value`
- `base_ratio`
- `base_damage / final_damage`
- `tags_mask`

### 已有 dump

已有：
- `debug_dump_last_damage()`
- `debug_dump_damage_range(from_index)`
- `debug_dump_last_dot()`
- `debug_dump_dot_range(from_index)`

因此 H3 的功能已经存在，但缺少“稳定输出契约”的测试。

---

## 本轮新增（契约 + 单测）

### 1) 契约：trace_* 必须生成结构完整的 trace

- `trace_damage()` 必须写入 DamageTrace 的所有字段，且 `stage_triggers` 必须是 Dictionary（允许为空/阶段数组为空）。
- `trace_dot_tick()` 必须写入 DotTrace 的所有字段。

### 2) 契约：debug_dump_* 输出稳定

目标是“可用于断言”和“易读”，因此只锁死最关键的可读点：
- `debug_dump_damage_range(i)`：
  - 非空时返回多行字符串，每行包含前缀 `[DamageTrace]`
  - 行内包含 `turn=`、`atk=`、`def=`、`base=`、`final=`
- `debug_dump_dot_range(i)`：
  - 非空时返回多行字符串，每行包含前缀 `[DotTrace]`
  - 行内包含 `turn=`、`src=`、`tgt=`、`read=`、`base=`、`final=`

> 注意：不锁死完整文本内容，避免未来扩展字段导致测试不必要地频繁调整。

---

## 单测（必须）

新增 3 个 GUT：

1) `test_replay_damage_trace_fields.gd`
- 跑一次 `deal_damage`（传入 replay）
- 断言 `damage_traces.size()==1`
- 断言 trace 的字段类型/存在性（尤其 `triggered_inst_ids`/`stage_triggers`）

2) `test_replay_dot_trace_fields.gd`
- 构造一个 DOT（沿用 rpg_tests fixture）
- 触发一次 TurnStart tick（传入 replay）
- 断言 `dot_traces.size()>=1` 且字段完整

3) `test_replay_debug_dump_range.gd`
- 产生 2 条 damage trace 与 2 条 dot trace
- 对 range dump 做“包含关键子串 + 行数”的断言

---

## 验收标准

- 新增测试全绿
- checklist：H1~H3 勾选为完成并提交

