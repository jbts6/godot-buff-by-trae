# OmniBuff UI Demo RPG Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重构并扩展 `addons/omnibuff/demo/buff_ui_demo.*`，使其以“scenario 列表”的方式覆盖 `addons/omnibuff/tests/rpg/` 的主要能力点，并支持切换数据集（base_demo / rpg_tests）。

**Architecture:** UI 负责选择 dataset + scenario；scenario 执行前统一 reset；每个 scenario 只跑一段很短的“可视化脚本”，并把关键输出写进日志框（stats / buff instances / replay dumps / dot ticks）。

**Tech Stack:** Godot 4.7 + GDScript。

---

## 0) 文件清单

**UI Demo：**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.tscn`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

**文档：**
- Modify: `godot-buff/addons/omnibuff/README.md`

---

## Task 1：重构 UI（scenario 列表 + dataset 选择）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.tscn`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: 更新场景布局**

在 `buff_ui_demo.tscn` 增加：
- `OptionButton`：`DatasetSelect`（base_demo / rpg_tests）
- `ItemList`：`ScenarioList`
- `Button`：`BtnRunSelected`
- `Button`：`BtnRunAll`（可选）

布局建议：
- 顶部：Status + Controls
- 中间：左侧 ScenarioList，右侧 LogBox

- [ ] **Step 2: 代码接入 UI**

在 `buff_ui_demo.gd` 增加 onready 引用：
```gdscript
@onready var dataset_select: OptionButton = %DatasetSelect
@onready var scenario_list: ItemList = %ScenarioList
@onready var btn_run_selected: Button = %BtnRunSelected
```

- [ ] **Step 3: 引入 Scenario 注册表**

```gdscript
var _scenarios: Array = []

func _register_scenarios() -> void:
	_scenarios = [
		{"id":"stat_percent_layers", "title":"Stats / Percent Layers", "dataset":"rpg_tests", "fn": Callable(self, "_sc_stat_percent_layers"),
		 "covers":["test_stat_percent_layers.gd","test_percent_modifier.gd"]},
	]
```

并把列表渲染到 UI：
```gdscript
scenario_list.clear()
for s in _scenarios:
	scenario_list.add_item(String(s.title))
```

- [ ] **Step 4: 提交**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.tscn addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m "refactor(demo): switch omnibuff ui demo to scenario runner"
```

---

## Task 2：支持 dataset 切换（base_demo / rpg_tests）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: 抽象 load_dataset(dataset_id)**

```gdscript
func _dataset_manifest_path(dataset_id: String) -> String:
	if dataset_id == "rpg_tests":
		return "res://data/rpg_tests/manifest.json"
	return "res://data/base_demo/manifest.json"

func _load_dataset_by_id(dataset_id: String) -> bool:
	var manifest_path: String = _dataset_manifest_path(dataset_id)
	var result = ManifestLoader.load_dataset_full(manifest_path, true)
	...
	return true
```

- [ ] **Step 2: dataset_select 绑定**

```gdscript
dataset_select.clear()
dataset_select.add_item("base_demo")
dataset_select.add_item("rpg_tests")
```

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m "feat(demo): allow switching dataset in ui demo"
```

---

## Task 3：增加“运行框架”（reset + 增量 dump + 轻量自检）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: reset 统一入口**

```gdscript
func _reset_run() -> void:
	replay = Replay.new()
	pipe = DamagePipeline.new()
```

- [ ] **Step 2: 增量 dump helper**

```gdscript
func _dump_replay_delta(dmg_from: int, dot_from: int) -> void:
	_log(replay.debug_dump_damage_range(dmg_from))
	_log(replay.debug_dump_dot_range(dot_from))
```

- [ ] **Step 3: run_selected**

```gdscript
func _run_selected() -> void:
	var idx: int = scenario_list.get_selected_items()[0]
	var s: Dictionary = _scenarios[idx]
	_reset_run()
	_load_dataset_by_id(String(s.dataset))
	var dmg_from: int = replay.damage_traces.size()
	var dot_from: int = replay.dot_traces.size()
	_log("=== " + String(s.title) + " ===")
	_log("covers: " + str(s.covers))
	(s.fn as Callable).call()
	_dump_replay_delta(dmg_from, dot_from)
```

- [ ] **Step 4: 提交**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m "feat(demo): add runner helpers and delta dumps"
```

---

## Task 4：逐类补齐 RPG scenarios（最小但覆盖广）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

> 每个 scenario 都要在日志里打印：关键数值 + buff instances + replay 增量。

### 4.1 Stats

- [ ] **Step: Percent layers**
覆盖：`test_stat_percent_layers.gd`

实现要点：对单实体依次 apply `buff_test_weapon_atk_flat_10` / `buff_test_passive_atk_flat_5` / `buff_atk_pct_5` / `buff_test_trinket_atk_pct_10` / `buff_test_total_atk_pct_20`，打印 ATK。

- [ ] **Step: Priority & override / clamp**
覆盖：`test_stat_priority_and_override.gd`、`test_stat_clamp.gd`

### 4.2 Lifecycle

- [ ] **Step: expire / refresh policy / stacking / while-condition**
覆盖：`test_buff_lifecycle_*.gd`

实现要点：用 `TurnComponent` 推进回合（`on_turn_end/on_turn_start`），打印实例 remaining_turns/stacks 与 active 状态。

### 4.3 Remove + Dispel

- [ ] **Step: remove_by_* + dispel_by_* + undispellable & immunity**
覆盖：`test_buff_removal_a5.gd`、`test_dispel_by_*.gd`、`test_undispellable_and_immunity.gd`

### 4.4 Damage pipeline

- [ ] **Step: shield absorb / damage reduction / stage traces**
覆盖：`test_shield_absorb.gd`、`test_damage_reduction.gd`、`test_damage_pipeline_stage_traces_present.gd`

### 4.5 Events

- [ ] **Step: event add base damage / shatter shield / chance apply determinism**
覆盖：`test_event_add_base_damage.gd`、`test_event_shatter_shield_before_apply.gd`、`test_event_chance_apply_buff_determinism.gd`

### 4.6 DOT

- [ ] **Step: dot actions filter / mul-add-set-clear / aggregate / merge**
覆盖：`test_dot_actions_*`、`test_dot_aggregate_*`、`test_dot_merge_*`

### 4.7 Multi-hit / AOE / Replay

- [ ] **Step: multihit each hit applies DOT**
覆盖：`test_multihit_each_hit_applies_dot.gd`

- [ ] **Step: aoe multitarget multihit per-target hit/crit + DOT**
覆盖：`test_aoe_multitarget_multihit_per_target_hit_crit_and_dot.gd`

- [ ] **Step: replay fields + debug dump range**
覆盖：`test_replay_*`

- [ ] **Step: roll_key deterministic RNG**
覆盖：`test_roll_key_makes_hit_crit_independent_per_strike.gd`

- [ ] **Step: full turn script battle**
覆盖：`test_full_turn_script_battle.gd`

- [ ] **Step: 提交（该大任务可能拆成多次 commit）**

建议按类别拆提交，例如：
```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m "feat(demo): add rpg scenarios (stats/lifecycle)"
```

---

## Task 5：文档更新

**Files:**
- Modify: `godot-buff/addons/omnibuff/README.md`

- [ ] **Step 1: 增加“UI demo 覆盖 rpg_tests”说明**
写清楚：
- UI demo 路径
- 建议在 Editor 启用 OmniBuff 插件后使用
- rpg_tests 用于更完整演示

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/README.md
git -C godot-buff commit -m "docs: document rpg coverage in omnibuff ui demo"
```

---

## Self-Review Checklist

- [ ] 是否至少覆盖了 spec 中 A~I 每个大类的 1 个 scenario？
- [ ] 是否支持 base_demo/rpg_tests 切换且不会残留旧 dataset 的引用？
- [ ] Scenario 是否每次运行前 reset，避免多次点击累积污染？
- [ ] 是否有任何 `:=` 导致解析期类型推断问题？（尽量显式类型或用 `var x = ...`）

