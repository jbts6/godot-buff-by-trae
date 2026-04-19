# TurnManager 闭环集成（2v2 + OmniBuff 数据集 + TurnSkillSystem 技能）设计 Spec

日期：2026-04-19  
范围：在**不推翻现有 TurnManager 实现**的前提下，补齐“战斗闭环必须”的集成与一致性口径，并提供可运行的 2v2 demo 与回归测试。  

插件路径约定（本工程固定）：
- OmniBuff：`res://addons/omnibuff`
- TurnSkillSystem：`res://addons/turn_skill_system`
- TurnManager：`res://addons/turn_manager`

数据与技能来源（本次固定）：
- OmniBuff 数据集：`res://data/rpg_tests/manifest.json`（以及其引用的 `res://data/base_demo/enums.json` 等）
- 技能 JSON：`res://addons/turn_skill_system/data/skills/*`（使用 `act_demo_single/act_demo_cross/act_demo_heal` 等）

---

## 1. 背景：当前实现状态（基于代码检查的事实）

当前 `res://addons/turn_manager` 已包含：
- `runtime/turn_manager.gd`：状态机、队列排序、事件派发、调用 `SkillRuntime.cast_to_cell`。
- `runtime/battle_context.gd`：上下文容器、尝试从 `/root/TurnSkillRuntime` 拉取 grid/event_bus/omnibuff_adapter/aura/passive。
- `demo/demo_battle.gd/.tscn`：demo 骨架（但未真正 `setup()/start_battle()`，且 unit 未注入 stats/buffs）。
- `tests/*`：排序测试与事件冒烟测试（目前未覆盖“cell 稳定排序 row-major”与“HP 判死走 ds.stat_id + stats.get_final”）。

本 spec 目标是把上述“骨架”收敛成**可运行闭环**：
> 2v2 开战 → 每轮重排 → 每个 actor 自动选择并施放 `act_demo_single` → 结算伤害 → 死亡判定 → 胜负结束。

---

## 2. 统一口径（必须落实）

### 2.1 稳定排序（cell）
当 `TurnManager.stable_order_mode == "cell"` 时，稳定排序 key 必须是：

> `cell_key = cell.x * 1000 + cell.y`

即：**row-major**（先 x 再 y），与 `turn_skill_system/runtime/grid.gd` 中 `get_first_enemy()` 的稳定排序口径保持一致。

### 2.2 死亡判定（hp_stat_id + OmniBuff Stats）
当 unit 未提供 `is_dead()` 时，TurnManager 的默认死亡判定必须为：
1. `hp_int = context.dataset.stat_id(hp_stat_id)`  
2. `hp = unit.stats.get_final(hp_int)`  
3. `hp <= 0` 判死

并要求：
- `hp_stat_id` 可配置，默认 `"HP"`。
- 若 `hp_int < 0`（dataset 不包含该 stat），应明确报错/阻断（避免静默错误导致战斗逻辑不可预测）。

### 2.3 TurnStart/TurnEnd tick 口径（单位回合序号）
延续既定决策：
- `turn_index`：按“单位回合序号”（每个 actor 走完 TURN_END 后 +1）
- `round_index`：每轮队列重建后 +1

`OmniTurnComponent` 的调用口径：本次闭环以“每个 actor 的 turn_start/turn_end tick 只处理该 actor”为准（传入 `[actor_id]`）。  
> 若未来要变更为“全体 tick”，需另开 spec（将 tick 移到 round_start/end 并传全量 entity_ids_sorted）。

---

## 3. BattleBootstrap（闭环必须模块）设计

### 3.1 输入
- `manifest_path = "res://data/rpg_tests/manifest.json"`
- `units_spec`：2v2 的单位初始化描述（entity_id、camp、cell、speed、初始数值）
- 依赖：工程启用 `omnibuff` 与 `turn_skill_system` 插件（保证 Autoload 存在：`/root/OmniBuff`、`/root/TurnSkillRuntime`）

### 3.2 输出
构建出可用于 `TurnManager.setup(context, units)` 的：
- `BattleContext`（必须包含：grid/event_bus/dataset/enums_rt/runtime_dict/turn_component/omnibuff_adapter/aura_manager/passive_manager）
- `units: Array[Node]`（每个 unit Node 满足契约：`entity_id/camp/cell/stats/buffs/get_speed()`）

### 3.3 必须动作
1) **编译 OmniBuff 数据集**
- `OmniBuff.ManifestLoader.load_dataset_full(manifest_path, true)`
- `OmniBuff.EnumsRuntime.from_enums_json(result.enums)`
- `OmniBuff.DatasetCompiler.compile(result.manifest, enums_rt, result.sources)`

2) **创建 2v2 单位并注入 stats/buffs**
- stats：`OmniBuff.StatsComponent.new(entity_id, ds)`
- buffs：`OmniBuff.BuffCore.new(ds, enums_rt)`
- 写入初始基础值（至少 HP、ATK；避免 HP 默认为 0 导致立刻死亡）
  - `hp_id = ds.stat_id("HP")` → `stats.add_base(hp_id, 100)`
  - `atk_id = ds.stat_id("ATK")` → `stats.add_base(atk_id, 50)`（支撑 `act_demo_single` 的伤害公式）

3) **构建 runtime_dict**
- `runtime_dict.stats_by_entity[eid] = unit.stats`
- `runtime_dict.buff_by_entity[eid] = unit.buffs`

4) **绑定 TurnSkillRuntime**
- `/root/TurnSkillRuntime.ensure_ready()`
- `TurnSkillRuntime.grid.set_units(units)`
- `TurnSkillRuntime.omnibuff.setup(ds, enums_rt, runtime_dict)`

> 注：本 spec 不要求自动注册被动/光环；闭环最小目标是“主动技能 + 伤害 + 死亡 + 胜负”。后续要演示被动/光环，可在 demo 中追加注册步骤。

---

## 4. 2v2 Demo 场景（闭环验证载体）

### 4.1 场景与脚本
位置：
- `res://addons/turn_manager/demo/demo_battle.tscn`
- `res://addons/turn_manager/demo/demo_battle.gd`

要求：
- demo 必须在 `_ready()` 内：
  1) 执行 BattleBootstrap（见第 3 节）
  2) 调用 `turn_manager.setup(context, units)`
  3) 连接 `action_requested` 信号并自动提交命令（见 4.2）
  4) 调用 `turn_manager.start_battle()`

### 4.2 行动策略（暂用自动 AI）
- 每个 actor 回合：自动施放 `act_demo_single`
- 目标选择：找到一个敌方单位，取其 `cell`，作为 `TurnCommand.primary_cell`
- command：
  - `skill_id = "act_demo_single"`
  - `primary_cell = enemy.cell`

### 4.3 验收标准（demo）
运行 demo 场景时，应满足：
- 能连续推进多个单位回合（至少 1 轮以上）
- 事件总线能看到 `turn_started/action_started/action_finished/turn_ended` 组合
- 至少有一个单位在若干回合后 HP 归零，触发 `unit_died`
- 最终触发 `battle_ended`（胜负成立）

---

## 5. 回归测试（GUT）

### 5.1 新增/调整的测试覆盖点
1) **cell 稳定排序 row-major**  
当同速同阵营时，`cell(0,1)` 必须在 `cell(0,2)` 之前；所有 `cell.x==0` 必须在 `cell.x==1` 之前。

2) **死亡判定走 dataset.stat_id + stats.get_final**  
当 unit 没有 `is_dead()` 方法时，使用 FakeDataset/FakeStats 进行断言：
- HP>0 → 不死
- HP<=0 → 判死

### 5.2 测试运行命令（工程约定）
脚本：`./run_gut_tests.sh`  
说明：需要设置 `GODOT_BIN` 指向本机 Godot 可执行文件（CI/本机环境约束）。

---

## 6. 与现有实现的差异清单（本 spec 要求的“必改点”）

为满足闭环，必须保证以下事实成立：
1) `TurnManager` 的 cell 稳定排序 key 使用 `cell.x * 1000 + cell.y`
2) `TurnManager.is_dead()` 默认实现使用 `dataset.stat_id(hp_stat_id)` + `stats.get_final()`
3) `BattleContext` 中 pipeline 的脚本路径/构建方式与 omnibuff 实际位置一致（不允许引用不存在路径）
4) `BattleContext.build_from_autoload()` 不应假设 OmniBuff 提供 `get_dataset/get_enums`（dataset/enums 必须由 BattleBootstrap 注入）
5) demo 必须真正 `setup/start_battle` 且构建 2v2、注入 stats/buffs、并用 `act_demo_single`

