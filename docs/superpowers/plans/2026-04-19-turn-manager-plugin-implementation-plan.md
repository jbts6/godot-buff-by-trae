# TurnManager Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`+ [x]`) syntax for tracking.

**Goal:** 在 `res://addons/turn_manager/` 实现一个 Godot 4.x 插件：提供回合制战斗 TurnManager（每轮按速度重排），并与 `addons/omnibuff` + `addons/turn_skill_system` 通过“单位 Node 契约 + BattleEventBus 事件时序”完成闭环集成。

**Architecture:** TurnManager 作为场景节点（Node）驱动战斗状态机与行动队列，是“战斗流程的唯一权威”。技能/效果由 `turn_skill_system` 负责（`SkillRuntime.cast*`），数值/Buff/DOT tick 由 `omnibuff` 负责（`OmniTurnComponent`）。TurnManager 在关键节点向 `BattleEventBus` 派发事件以驱动被动/光环/伤害链。

**Tech Stack:** Godot 4.x, GDScript, EditorPlugin（可选 Autoload 安装能力）, OmniBuff, Turn Skill System, GUT（单元测试）。

---

## 0) File structure（本计划将创建/修改的文件）

### Create（插件）
+ [x] `addons/turn_manager/plugin.cfg`
+ [x] `addons/turn_manager/plugin.gd`（EditorPlugin：启用/禁用插件；不强制安装 Autoload）
+ [x] `addons/turn_manager/runtime/turn_manager.gd`（核心 TurnManager Node）
+ [x] `addons/turn_manager/runtime/battle_context.gd`（战斗上下文容器：持有 grid/event_bus/ds/enums_rt/runtime_dict/turn_component 等）
+ [x] `addons/turn_manager/runtime/turn_command.gd`（最小：CastSkillCommand）
+ [x] `addons/turn_manager/runtime/victory_condition.gd`（默认：一方全灭）

### Create（测试）
+ [x] `addons/turn_manager/tests/test_turn_queue_sorting.gd`
+ [x] `addons/turn_manager/tests/test_event_sequence_smoke.gd`

### Create（demo，可选但强烈建议）
+ [x] `addons/turn_manager/demo/demo_battle.tscn`
+ [x] `addons/turn_manager/demo/demo_battle.gd`

### Create（文档）
+ [x] `addons/turn_manager/README.md`

---

## Task 1: Scaffold 插件（可启用/禁用）

**Files:**
- Create: `addons/turn_manager/plugin.cfg`
- Create: `addons/turn_manager/plugin.gd`

+ [x] 创建 `plugin.cfg`（名称、描述、作者、版本、script 路径）
+ [x] 创建 `plugin.gd`（EditorPlugin）
  + [x] `_enter_tree()`：打印启用日志（风格对齐 omnibuff/turn_skill_system）
  + [x] `_exit_tree()`：打印禁用日志
  + [x] 不强制写入 Autoload（保持 TurnManager 作为场景节点的推荐用法）
+ [x] 手动验证：Godot 编辑器中可正常勾选/取消插件，不报错

---

## Task 2: BattleContext（与两个插件的运行时对接封装）

**Files:**
- Create: `addons/turn_manager/runtime/battle_context.gd`

+ [x] 定义 BattleContext 的“必需字段”（与 spec 对齐）：
  - grid（turn_skill_system 的 Grid）
  - event_bus（BattleEventBus）
  - dataset（ds）、enums_rt
  - runtime_dict（stats_by_entity / buff_by_entity）
  - turn_component（OmniTurnComponent）
  - omnibuff_adapter / passive_manager / aura_manager（从 TurnSkillRuntime autoload 获取或注入）
+ [x] 定义 BattleContext 的“构建入口”（两种模式都要支持）：
  + [x] **Autoload 优先**：若存在 `/root/TurnSkillRuntime`，调用 `ensure_ready()` 并从其字段读取模块引用
  + [x] **手动注入**：允许调用方直接把上述字段注入（便于单元测试/离线模拟）
+ [x] 验收标准：
  + [x] 缺少 ds/enums_rt/runtime_dict 时能够清晰报错（避免进入战斗后才发现 cast 必失败）

---

## Task 3: TurnCommand（最小命令集：CastSkill）

**Files:**
- Create: `addons/turn_manager/runtime/turn_command.gd`

+ [x] 定义 TurnCommand 的最小数据结构：
  - kind 固定为 `cast_skill`
  - skill_id
  - primary_cell（统一使用 cell；unit 目标由外部转换为 cell）
  - extra（可选扩展字段）
+ [x] 验收标准：
  + [x] UI/AI 能够仅通过构造 TurnCommand 把一次施法请求完整表达出来

---

## Task 4: VictoryCondition（默认：一方全灭）

**Files:**
- Create: `addons/turn_manager/runtime/victory_condition.gd`

+ [x] 实现默认胜负判定：分别统计 ally/enemy 存活单位数（基于 TurnManager 的“死亡判定策略”）
+ [x] 输出结果格式与 TurnManager `battle_ended(result)` 对齐（至少包含 winner/reason）
+ [x] 验收标准：
  + [x] 当某阵营全部死亡时，TurnManager 可在本回合结算后进入 BATTLE_END 并发出 battle_ended

---

## Task 5: TurnManager 核心状态机（不含 UI/动画，仅发信号与 emit 事件）

**Files:**
- Create: `addons/turn_manager/runtime/turn_manager.gd`

+ [x] 定义 TurnManager 状态枚举（与 spec 对齐）并保证“单入口推进”（例如一个 `_advance()` 驱动，不要多处同时推进导致竞态）
+ [x] 实现 `setup(context, units)`：
  + [x] 记录 units（直接使用 Node 作为 Grid unit）
  + [x] 调用 `context.grid.set_units(units)`
  + [x] 生成 runtime_dict（stats_by_entity / buff_by_entity），并放入 context（或校验注入值一致）
  + [x] 建立稳定顺序（spawn_index 或 cell）
+ [x] 实现 `start_battle()` / `stop_battle()`（资源清理、断开连接等）
+ [x] 实现“当前行动者”与“等待玩家输入”的内部状态（防止重复 submit）

---

## Task 6: 行动队列（每轮重排：speed + 玩家优先 + 稳定排序）

**Files:**
- Modify: `addons/turn_manager/runtime/turn_manager.gd`

+ [x] 实现 `unit.get_speed()` 读取策略：
  + [x] 若缺少方法，给出清晰错误信息（因为你已确认 speed 来源只用 get_speed）
+ [x] 实现 `build_turn_queue_for_round()`：
  + [x] 过滤存活单位
  + [x] 排序键：
    - speed（降序，get_speed）
    - camp_priority（ally 优先）
    - stable_order（spawn_index 或 cell）
+ [x] 发出 `round_started(round_index, queue)` 信号（queue 为 Node 数组）
+ [x] 单元测试覆盖：
  + [x] 不同 speed
  + [x] 同 speed 不同阵营（玩家优先）
  + [x] 同 speed 同阵营（稳定排序）

---

## Task 7: TurnStart/TurnEnd tick（对接 OmniTurnComponent + AuraManager）

**Files:**
- Modify: `addons/turn_manager/runtime/turn_manager.gd`

+ [x] 维护两个计数器：
  + [x] `round_index`：每轮 +1
  + [x] `turn_index`：按“单位回合序号”（每个单位完成一次 turn_end 后 +1）
+ [x] 在 TurnStart 阶段执行固定顺序（与 spec 对齐）：
  + [x] 发出 TurnManager 自身信号 `turn_started(actor, turn_index)`
  + [x] `event_bus.emit_event(EventNames.TURN_STARTED, {turn_index, actor_id})`
  + [x] `turn_component.on_turn_start(entity_ids_sorted, buff_by_entity, stats_by_entity, pipeline, ds, replay)`（按 context 字段存在性选择参数版本）
  + [x] `aura_manager.refresh_all()`（若存在）
+ [x] 在 TurnEnd 阶段执行固定顺序（与 spec 对齐）：
  + [x] `turn_component.on_turn_end(...)`
  + [x] `event_bus.emit_event(EventNames.TURN_ENDED, {turn_index, actor_id})`
  + [x] 发出 `turn_ended(actor, turn_index)`
  + [x] `aura_manager.refresh_all()`（若存在）
  + [x] `turn_index += 1`
+ [x] 验收标准：
  + [x] 在无技能/仅跳过的回合，也会执行 turn_start 与 turn_end tick（保证 DOT/buff 时钟前进）

---

## Task 8: ResolveAction（调用 SkillRuntime.cast_to_cell 并派发 ACTION_* 事件）

**Files:**
- Modify: `addons/turn_manager/runtime/turn_manager.gd`

+ [x] 定义“玩家提交命令”的唯一入口 `submit_player_command(command)`：
  + [x] 仅在 REQUEST_ACTION 状态可提交；否则拒绝（避免 UI 误触导致状态破坏）
+ [x] 在 RESOLVE_ACTION 阶段：
  + [x] `event_bus.emit_event(EventNames.ACTION_STARTED, {...})`
  + [x] 调用 `SkillRuntime.cast_to_cell(skill_id, actor, primary_cell, extra)`（extra 必须补齐 grid/dataset/enums_rt/runtime_dict/turn_index；以及 hp_stat_id 等必要配置若你想下沉到技能侧）
  + [x] `event_bus.emit_event(EventNames.ACTION_FINISHED, {...})`（至少包含 ok/errors 摘要）
  + [x] 若 cast 失败：默认依然结束本回合（与 spec 对齐）
+ [x] 冒烟测试：
  + [x] 用 turn_skill_system 自带的 demo skill_id（或你项目内任意一个 active skill）跑通一次 cast

---

## Task 9: 死亡判定策略（hp_stat_id 可配置，默认 "HP"）

**Files:**
- Modify: `addons/turn_manager/runtime/turn_manager.gd`

+ [x] 实现 `is_dead(actor)`：
  + [x] 若 actor 提供 `is_dead()` 方法：优先调用
  + [x] 否则使用 `actor.stats` + `hp_stat_id` 从 dataset 找到 stat id 并读当前值，判定 `<= 0`
  + [x] 缺少 hp_stat_id 或 stat 不存在：报错（不要静默错误）
+ [x] 在每次行动结算后执行“死亡清理”：
  + [x] 对新死亡单位派发 `EventNames.UNIT_DIED`
  + [x] 从后续队列跳过/移除（保持不会再行动）
+ [x] 验收标准：
  + [x] 死亡单位不会再进入 REQUEST_ACTION
  + [x] 胜负条件能在死亡清理后正确触发

---

## Task 10: 单元测试（GUT）

**Files:**
- Create: `addons/turn_manager/tests/test_turn_queue_sorting.gd`
- Create: `addons/turn_manager/tests/test_event_sequence_smoke.gd`

+ [x] Sorting 测试：
  + [x] 构造最小 unit Node（只要满足 entity_id/camp/cell/stats/buffs/get_speed 即可）
  + [x] 断言每轮队列满足排序规则
+ [x] Event sequence 冒烟测试：
  + [x] 构造最小 BattleContext（参考 `addons/turn_skill_system/demo/demo_battle.gd` 的 dataset/runtime_dict/grid 初始化方式）
  + [x] 运行 1 个单位回合并捕获 `event_bus` 的 events
  + [x] 断言至少包含 `TURN_STARTED -> ACTION_STARTED -> ... -> ACTION_FINISHED -> TURN_ENDED`

> 说明：本计划按你的要求“不包含具体代码”。测试的具体实现细节在执行阶段按现有 `addons/omnibuff/tests` 与 `addons/turn_skill_system/demo` 风格落地即可。

---

## Task 11: Demo 场景（可选但建议）

**Files:**
- Create: `addons/turn_manager/demo/demo_battle.tscn`
- Create: `addons/turn_manager/demo/demo_battle.gd`

+ [x] 提供一个最小战斗演示：
  + [x] 加载 omnibuff dataset（用你工程现有 manifest 路径）
  + [x] 构造 2~4 个单位 Node（满足字段契约 + get_speed）
  + [x] 创建 TurnManager 节点并 `setup/start_battle`
  + [x] 用简单 AI 自动提交 CastSkillCommand（或在控制台手动 submit）
+ [x] 验收标准：
  + [x] 能连续推进多个单位回合
  + [x] 能看到 event_bus 打印的事件流（便于调试）

---

## Task 12: 文档（README）

**Files:**
- Create: `addons/turn_manager/README.md`

+ [x] 写清楚：
  + [x] Unit Node 字段契约（必须字段 + get_speed + hp_stat_id）
  + [x] BattleContext 的两种构建模式（autoload 优先 / 手动注入）
  + [x] TurnManager 的信号与典型接入方式（UI/AI 如何监听与 submit 命令）
  + [x] 与 `turn_skill_system` 的事件对齐（TURN_*/ACTION_* 等）
  + [x] 最小示例（用文字描述 demo 如何跑）

---

## Self-Review（计划自检）

- 覆盖 spec 关键要求：
  + [x] 每轮按速度重排（get_speed）+ 同速玩家优先 + 稳定排序
  + [x] unit Node 直接作为 Grid unit
  + [x] TurnStart/TurnEnd tick 调用 OmniTurnComponent
  + [x] 通过 BattleEventBus 派发 TURN_*/ACTION_* 等事件
  + [x] hp_stat_id 可配置（默认 "HP"）
  + [x] 最小闭环 + 单元测试

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-19-turn-manager-plugin-implementation-plan.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

