# TurnManager 闭环集成（2v2）Implementation Plan（不含具体代码）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `res://addons/turn_manager` 在使用 `res://data/rpg_tests/manifest.json` + `res://addons/turn_skill_system/data/skills` 的条件下，提供一个可运行的 2v2 闭环 demo，并补齐一致性修复（cell row-major 稳定排序、HP 判死口径、BattleContext 构建策略），同时用 GUT 测试锁定关键行为。

**Architecture:** 不新增新框架；沿用现有 `TurnManager/BattleContext/TurnCommand/VictoryCondition`。通过 “BattleBootstrap（demo 内）” 显式编译 ds/enums_rt，构造 2v2 unit（注入 stats/buffs），建立 runtime_dict，并绑定到 `/root/TurnSkillRuntime`；TurnManager 负责驱动状态机并调用 `SkillRuntime.cast_to_cell("act_demo_single")`。

**Tech Stack:** Godot 4.7, GDScript, OmniBuff, TurnSkillSystem, GUT。

**Plugin Roots (固定路径约定):**
- OmniBuff：`res://addons/omnibuff`
- TurnSkillSystem：`res://addons/turn_skill_system`
- TurnManager：`res://addons/turn_manager`

---

## 0) 目标文件清单（本计划将修改/新增）

### Modify（实现修复）
- [ ] `res://addons/turn_manager/runtime/turn_manager.gd`
- [ ] `res://addons/turn_manager/runtime/battle_context.gd`
- [ ] `res://addons/turn_manager/demo/demo_battle.gd`

### Modify（测试）
- [ ] `res://addons/turn_manager/tests/test_turn_queue_sorting.gd`
- [ ] `res://addons/turn_manager/tests/test_event_sequence_smoke.gd`

### Reference（数据/技能，不改）
- `res://data/rpg_tests/manifest.json`
- `res://addons/turn_skill_system/data/skills/active/act_demo_single.json`

---

## Task 1（RED）: 为 cell row-major 稳定排序新增回归测试

**Files:**
- Modify: `res://addons/turn_manager/tests/test_turn_queue_sorting.gd`

- [ ] Step 1: 新增一个测试用例，构造 3 个同速同阵营单位，cell 分别为：
  - (0,2)、(1,0)、(0,1)
- [ ] Step 2: 设置 `stable_order_mode="cell"`，调用 `_build_turn_queue()` 后断言顺序为：
  1) cell (0,1)
  2) cell (0,2)
  3) cell (1,0)
- [ ] Step 3: 运行 GUT（本机/CI 环境）确认该测试 FAIL，失败原因应指向当前 cell key 算法不是 row-major。

---

## Task 2（GREEN）: 修复 TurnManager 的 cell 稳定排序 key

**Files:**
- Modify: `res://addons/turn_manager/runtime/turn_manager.gd`

- [ ] Step 1: 在 `_sort_units()` 的 `stable_order_mode=="cell"` 分支中，将 cell key 统一为：
  - `cell.x * 1000 + cell.y`
- [ ] Step 2: 运行 GUT，确认 Task 1 新增测试通过且原有排序测试仍通过。

---

## Task 3（RED）: 为 hp_stat_id 判死口径新增回归测试（dataset.stat_id + stats.get_final）

**Files:**
- Modify: `res://addons/turn_manager/tests/test_event_sequence_smoke.gd`

- [ ] Step 1: 新增 FakeDataset（提供 `stat_id("HP")->0`）与 FakeStats（提供 `get_final(0)->hp`）的最小实现
- [ ] Step 2: 新增测试：构造一个**没有 is_dead() 方法**的 unit，仅提供 stats 字段：
  - hp=10 时 `turn_manager.is_dead(unit)` 必须为 false
  - hp=0 时必须为 true
- [ ] Step 3: 运行 GUT 确认测试 FAIL，失败原因应指向当前 `is_dead()` 使用了不存在的 `enums_rt.get_stat_id` 或 `stats.get_stat`。

---

## Task 4（GREEN）: 修复 TurnManager.is_dead() 的默认实现

**Files:**
- Modify: `res://addons/turn_manager/runtime/turn_manager.gd`

- [ ] Step 1: 调整 `is_dead(actor)`：
  - 优先 `actor.has_method("is_dead")`
  - 否则通过 `context.dataset.stat_id(hp_stat_id)` 获取 hp_int
  - 通过 `actor.stats.get_final(hp_int)` 读取当前 HP
  - `<=0` 判死
- [ ] Step 2: 明确错误策略：
  - dataset 缺失 hp_stat_id（hp_int<0）时，必须报错并给出可定位信息（包含 hp_stat_id 字符串）
  - unit 缺失 stats 时必须报错（包含 unit 名称或 entity_id）
- [ ] Step 3: 运行 GUT，确认 Task 3 新增测试通过，且 `VictoryCondition.check` 仍可工作。

---

## Task 5: 修复 BattleContext 的构建策略（autoload 只拉 runtime；ds/enums 由 bootstrap 注入）

**Files:**
- Modify: `res://addons/turn_manager/runtime/battle_context.gd`

- [ ] Step 1: 调整 `build_from_autoload()`：
  - 仅从 `/root/TurnSkillRuntime` 拉取并赋值：`grid/event_bus/omnibuff_adapter/passive_manager/aura_manager`
  - 删除/禁用对 `/root/OmniBuff.get_dataset/get_enums` 的假设
- [ ] Step 2: 调整 `validate()` 的提示文案，使其明确：
  - `dataset/enums_rt` 必须由业务（demo/bootstrap）注入
- [ ] Step 3: 修复 pipeline 的引用路径或构造方式，使其与 omnibuff 的真实位置一致：
  - 不允许引用 `runtime/components/damage_pipeline.gd`（该路径在当前工程不存在）
  - pipeline 是否必须：本闭环 demo 可先不强制，但若提供，则应能被 `OmniTurnComponent` 用于 DOT tick

---

## Task 6: 2v2 demo 闭环（BattleBootstrap + 自动提交 act_demo_single）

**Files:**
- Modify: `res://addons/turn_manager/demo/demo_battle.gd`

- [ ] Step 1: 在 `_ready()` 中加入 BattleBootstrap（按 spec 文档要求）：
  - 编译 ds/enums_rt（manifest：`res://data/rpg_tests/manifest.json`）
  - 构造 2v2 unit Node（entity_id/camp/cell/get_speed）
  - 为每个 unit 注入 stats/buffs，并设置初始 HP/ATK（避免 HP=0）
  - 构建 runtime_dict（stats_by_entity/buff_by_entity）
  - 绑定到 `/root/TurnSkillRuntime`：`ensure_ready()` + `grid.set_units(units)` + `omnibuff.setup(ds,enums,runtime_dict)`
  - 构建 BattleContext：从 autoload 拉 runtime 组件，并手动注入 dataset/enums/runtime_dict
- [ ] Step 2: 连接 TurnManager 信号：
  - `action_requested`：为当前 actor 自动选择一个敌方 unit 的 cell，并提交 `TurnCommand("act_demo_single", enemy.cell)`
  - 打印 turn_started/turn_ended/battle_ended（便于人工验收）
- [ ] Step 3: 调用 `turn_manager.setup(ctx, units)` 与 `turn_manager.start_battle()`
- [ ] Step 4: 人工验收：
  - 战斗能推进多个回合
  - 逐步出现 HP 下降（可通过打印 actor/target 的 HP breakdown 或 after_damage 事件观测）
  - 有单位死亡触发 UNIT_DIED
  - 最终 battle_ended（胜负成立）

---

## Task 7: 事件与技能数据的“最小一致性检查”

**Files:**
- Modify (optional): `res://addons/turn_manager/tests/test_event_sequence_smoke.gd`

- [ ] Step 1: 将 event_sequence_smoke 扩展为验证：
  - ACTION_STARTED 的 `skill_id` 为 `act_demo_single`
  - ACTION_FINISHED 的 `ok` 为 true（至少在基础场景里）
- [ ] Step 2: 若 `SkillRuntime` 返回错误，优先检查：
  - TurnSkillRuntime 是否启用并 ensure_ready
  - extra 是否包含：grid/dataset/enums_rt/runtime_dict/turn_index
  - 技能 id 是否存在于 `res://addons/turn_skill_system/data/skills/index.json`

---

## Task 8: 文档同步（README 与 spec 链接）

**Files:**
- Modify: `res://addons/turn_manager/README.md`（可选但建议）

- [ ] Step 1: 在 README 中明确 demo 的真实依赖：
  - 使用 `res://data/rpg_tests/manifest.json`
  - 使用 `act_demo_single`（来自 turn_skill_system data/skills）
- [ ] Step 2: 记录“unit 必须注入 stats/buffs 且初始化 HP/ATK”的原因（避免新人踩坑）

---

## Self-Review（计划自检）

- [ ] cell 稳定排序 row-major：有测试锁定（Task 1）
- [ ] is_dead 默认实现：有测试锁定（Task 3）
- [ ] BattleContext 不再假设 OmniBuff 提供 dataset/enums getter（Task 5）
- [ ] demo 2v2 可闭环：能自动推进、能死人、能结束（Task 6）

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-19-turn-manager-bootstrap-2v2-integration-plan.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

