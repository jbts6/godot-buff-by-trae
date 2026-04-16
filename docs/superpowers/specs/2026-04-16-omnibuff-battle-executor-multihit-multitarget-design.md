# OmniBuff：BattleExecutor 多段/多目标（roll_key）设计

## 背景

当前已有：
- `OmniBattleExecutor`（最小可用）：COMMAND before/after + 单段单目标伤害
- `DamagePipeline.deal_damage(turn_index, roll_key, ...)`：命中/暴击确定性依赖 `(turn_index, roll_key, attacker_id, defender_id)`
- 事件系统：每次 `deal_damage` 会自然触发一整套 `DAMAGE/*`（因此“每次造成伤害触发被动”应挂在 `DAMAGE/AFTER_DEAL` 等阶段）

你确认本轮的触发语义选择为：
- **COMMAND 每条指令一次**
- **DAMAGE 每段/每目标一次**（因为每次 deal_damage 都会触发）

---

## 目标

扩展 `OmniBattleExecutor.execute_command()` 支持：

1) **multi-hit**：同一个指令里对同一目标打多段伤害（例如三连击）
2) **multi-target**：同一个指令里对多个目标依次造成伤害（例如群攻）
3) **roll_key 规则**：对每一次 `deal_damage` 递增 roll_key，保证命中/暴击在复盘中“每段独立、可控、可重复”
4) **Replay 关联**（最小）：仍记录一次 command（cast skill）；damage_traces 继续由 pipeline 记录（无需新增字段）

---

## 非目标（本轮不做）

- 不引入技能脚本 on_cast/on_hit 列表（仍保持 skill_defs 仅为数据承载）
- 不实现“追加伤害不触发追加”的通用机制（建议用 `DAMAGE` 事件 + tag/guard 设计在下一轮单独做）

---

## 数据协议（skill_defs 扩展）

在 `data/rpg_tests/skill_defs.json` 的 skill 字典中新增可选字段：

```jsonc
{
  "id": "skill_triple_slash",
  "name": "三连斩（3段递增）",
  "damage_type": "PHYSICAL",
  "element": "NONE",
  "tags": ["BUFF"],
  "base_damage": 0.0,

  "hit_count": 3,                 // 可选，默认 1
  "hit_base_damage": [12,14,18],  // 可选：若提供则覆盖 base_damage，并按 hit_index 取值

  "targeting": "FIRST",           // 可选：FIRST | ALL（默认 FIRST）
  "on_cast": [],
  "on_hit": []
}
```

解释：
- `hit_count`：多段次数；默认 1
- `hit_base_damage`：按段指定基础伤害；长度可为 1（所有段同值）或 >=hit_count（截断/取前 hit_count）
- `targeting`：
  - `FIRST`：只打 `ctx.targets[0]`
  - `ALL`：依次打 `ctx.targets[]` 中的每个目标（稳定顺序：entity_id 升序）

---

## 执行器行为

### 1) COMMAND 触发（指令级）

每条指令仅触发一次：
- `actor_buffs.emit_event(COMMAND, CMD_BEFORE, command_ctx)`
- 若 cancel：中止，不产生任何伤害
- 执行产生 1..N 次 `deal_damage`
- `actor_buffs.emit_event(COMMAND, CMD_AFTER, command_ctx)`

### 2) DAMAGE 触发（伤害级）

每一次 `deal_damage` 都会触发完整 DAMAGE 阶段，因此：
- “每次造成伤害追加xxx”应挂在 `DAMAGE/AFTER_DEAL`（每段一次）
- multi-hit/multi-target 都天然具备 per-hit 的触发粒度

### 3) roll_key 规则（核心）

对同一条指令内的第 k 次 `deal_damage`：
- `roll_key = k`（从 0 开始）

排序规则（稳定）：
1) target 维度：按 targets 的稳定顺序（建议在 executor 内部先 sort）
2) hit 维度：hit_index 从 0..hit_count-1

因此：
- 若 ALL 目标、hit_count=3，且 targets=[A,B]：调用顺序为
  - A hit0 (roll=0), A hit1 (1), A hit2 (2), B hit0 (3), B hit1 (4), B hit2 (5)

---

## 测试与 Demo（验收）

### Tests
新增 `tests/rpg/test_battle_executor_multihit_multitarget.gd`：

1) multi-hit：三连击对单目标 → replay.damage_traces 增加 3 条，且每条 roll_key 不同（0,1,2）
2) multi-target：群攻对 2 个目标 → replay.damage_traces 增加 2 条（FIRST/ALL）
3) 组合：ALL + hit_count=2 + 2 targets → traces=4，roll_key=0..3 且顺序稳定

### Demo
`buff_ui_demo` 新增 2 个场景：
- executor_multihit_triple_slash
- executor_multitarget_all

---

## 验收标准

- [ ] executor 支持 multi-hit/multi-target 且 roll_key 递增
- [ ] tests 全绿，且 traces 顺序稳定
- [ ] demo 可复现并可用 HUD/日志解释

