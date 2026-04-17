# turn_skill_system M1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `turn_skill_system` 补齐 M1（结算闭环 + 稳定性）：heal 正式落地、cast 返回结构/错误码稳定、DamagePipeline 参数透传可断言、失败/边界用例补齐，并确保全部 GUT tests headless 通过。

**Architecture:** 以测试驱动（RED→GREEN 双提交）推进；将“可回放/可追溯”的结算逻辑收敛到 `OmniBuffAdapter`，`SkillRuntime` 只负责组装 ctx 与收集结果；通过 adapter 返回的 `meta` 提供参数透传的可观测性（用于测试断言）。

**Tech Stack:** Godot 4.x, GDScript, GUT, OmniBuff

---

## 0) File structure（本迭代会改哪些文件）

**Modify（运行时）**
- `addons/turn_skill_system/runtime/omni_buff_adapter.gd`
- `addons/turn_skill_system/runtime/effects/heal_effect.gd`
- `addons/turn_skill_system/runtime/skill_runtime.gd`

**Create/Modify（测试）**
- `addons/turn_skill_system/tests/test_heal_effect_omnibuff.gd`（新）
- `addons/turn_skill_system/tests/test_cast_failure_shapes.gd`（新）
- `addons/turn_skill_system/tests/test_damage_pipeline_param_mapping.gd`（新）
- `addons/turn_skill_system/tests/test_simulate_cast_without_omnibuff.gd`（新/或改已有）

---

## Task 1: cast 返回结构稳定化（所有成功/失败路径字段齐全）

**Files:**
- Modify: `addons/turn_skill_system/runtime/skill_runtime.gd`
- Create: `addons/turn_skill_system/tests/test_cast_failure_shapes.gd`

- [ ] **Step 1: 写 failing test（RED）—失败分支字段齐全**

创建 `test_cast_failure_shapes.gd`：
```gdscript
extends GutTest

const SkillRuntime := preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid := preload("res://addons/turn_skill_system/runtime/grid.gd")

class U:
	extends RefCounted
	var entity_id := 1
	var camp := "ally"
	var cell := Vector2i(2, 1)
	var stats = null
	var buffs = null

func _assert_shape(r: Dictionary) -> void:
	assert_true(r.has("ok"))
	assert_true(r.has("simulation"))
	assert_true(r.has("skill_id"))
	assert_true(r.has("caster_id"))
	assert_true(r.has("targets"))
	assert_true(r.has("effects"))
	assert_true(r.has("events"))
	assert_true(r.has("resolved_formulas"))
	assert_true(r.has("rng_seed"))
	assert_true(r.has("errors"))
	assert_true(r.has("issues"))
	assert_true(r.has("predicted_deltas"))

func test_fail_unknown_skill_id_shape() -> void:
	var grid := Grid.new()
	var caster := U.new()
	grid.set_units([caster])

	var r := SkillRuntime.simulate_cast("__missing__", caster, null, {"grid": grid})
	assert_false(bool(r.get("ok", true)))
	_assert_shape(r)
	assert_true(r.get("errors", []).size() >= 1)
```

预期：当前若有字段缺失，测试 FAIL。

- [ ] **Step 2: 运行测试验证失败**

运行：`./run_gut_tests.sh`  
预期：`test_fail_unknown_skill_id_shape` FAIL（字段缺失或错误码不稳定）

- [ ] **Step 3: 最小实现（GREEN）—统一返回字段**

在 `SkillRuntime._fail()` 与成功返回路径中确保：
- 字段全部存在（即便是空数组/空字典）
- 失败路径的 `events` 至少捕获 `skill_cast_started`（若已 emit）
- `errors` 放稳定错误码字符串

- [ ] **Step 4: 运行测试验证通过**

运行：`./run_gut_tests.sh`  
预期：PASS

- [ ] **Step 5: Commit（GREEN）**

```bash
git add addons/turn_skill_system/runtime/skill_runtime.gd addons/turn_skill_system/tests/test_cast_failure_shapes.gd
git commit -m "fix(turn_skill_system): stabilize cast return shape (green)"
```

---

## Task 2: heal 正式落地（omnibuff adapter 层可回放）

**Files:**
- Modify: `addons/turn_skill_system/runtime/omni_buff_adapter.gd`
- Modify: `addons/turn_skill_system/runtime/effects/heal_effect.gd`
- Create: `addons/turn_skill_system/tests/test_heal_effect_omnibuff.gd`

- [ ] **Step 1: 写 failing test（RED）—heal 会改变 HP 且产生事件**

创建 `test_heal_effect_omnibuff.gd`：
```gdscript
extends GutTest

const SkillRuntime := preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid := preload("res://addons/turn_skill_system/runtime/grid.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")

class UnitWithOmni:
	extends RefCounted
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var stats
	var buffs
	func _init(eid: int, c: String, p: Vector2i, s, b) -> void:
		entity_id = eid
		camp = c
		cell = p
		stats = s
		buffs = b

func test_heal_effect_applies_and_emits_events() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt = loaded.enums_rt
	var ds = loaded.ds

	var a_stats := OmniBuff.StatsComponent.new(4001, ds)
	var t_stats := OmniBuff.StatsComponent.new(4002, ds)
	var a_buffs := OmniBuff.BuffCore.new(ds, enums_rt)
	var t_buffs := OmniBuff.BuffCore.new(ds, enums_rt)

	var caster := UnitWithOmni.new(4001, "ally", Vector2i(2, 1), a_stats, a_buffs)
	var target := UnitWithOmni.new(4002, "ally", Vector2i(1, 1), t_stats, t_buffs)

	var grid := Grid.new()
	grid.set_units([caster, target])

	var runtime_dict := {"stats_by_entity": {4001: a_stats, 4002: t_stats}, "buff_by_entity": {4001: a_buffs, 4002: t_buffs}}

	# 需要一个测试技能：on_hit 里包含 heal
	var r := SkillRuntime.cast("act_demo_heal", caster, null, {
		"grid": grid,
		"dataset": ds,
		"enums_rt": enums_rt,
		"runtime_dict": runtime_dict,
		"turn_index": 1
	})

	assert_true(bool(r.get("ok", false)))
	# 至少断言 heal effect 出现在 effects
	var has_heal := false
	for e in r.get("effects", []):
		if String(e.get("kind","")) == "heal":
			has_heal = true
	assert_true(has_heal)

	# 事件必须包含 before_heal/after_heal
	var types: Array[String] = []
	for ev in r.get("events", []):
		types.append(String(ev.get("type","")))
	assert_true(types.has("before_heal"))
	assert_true(types.has("after_heal"))
```

预期：当前 heal 不落地/缺技能/事件不全 → FAIL。

- [ ] **Step 2: 运行测试验证失败**

运行：`./run_gut_tests.sh`  
预期：FAIL（找不到 act_demo_heal 或 heal 未落地/事件缺失）

- [ ] **Step 3: 最小实现（GREEN）**

实现顺序：
1. 增加 demo 技能 `act_demo_heal.json`（active + FIRST + on_hit: heal）
2. `OmniBuffAdapter` 增加 `heal(...)`：
   - 若 omnibuff 当前已有“治疗接口”，直接调用（优先）
   - 若无：实现 `heal_v1`（最小一致性）：
     - 读取当前 HP
     - 通过 stats 的公开 API 写回（或调用 omnibuff stats component 的加成接口）
     - 使用 replay 记录（若 omnibuff 支持）
     - 返回 `{ok, final_heal, meta}`
3. `HealEffect` 在 simulation=false 时调用 adapter.heal，并把 `final_heal` 写入 effects/value，事件包含 before/after_heal

- [ ] **Step 4: 运行测试验证通过**

运行：`./run_gut_tests.sh`  
预期：PASS

- [ ] **Step 5: Commit**

```bash
git add addons/turn_skill_system/runtime/omni_buff_adapter.gd addons/turn_skill_system/runtime/effects/heal_effect.gd addons/turn_skill_system/data/skills/active/act_demo_heal.json addons/turn_skill_system/data/skills/index.json addons/turn_skill_system/tests/test_heal_effect_omnibuff.gd
git commit -m "feat(turn_skill_system): apply heal via omnibuff adapter (green)"
```

---

## Task 3: DamagePipeline 参数映射可断言（meta 可观测）

**Files:**
- Modify: `addons/turn_skill_system/runtime/omni_buff_adapter.gd`
- Create: `addons/turn_skill_system/tests/test_damage_pipeline_param_mapping.gd`

- [ ] **Step 1: 写 failing test（RED）**

创建 `test_damage_pipeline_param_mapping.gd`：
```gdscript
extends GutTest

const SkillRuntime := preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid := preload("res://addons/turn_skill_system/runtime/grid.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")

class UnitWithOmni:
	extends RefCounted
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var stats
	var buffs
	func _init(eid: int, c: String, p: Vector2i, s, b) -> void:
		entity_id = eid
		camp = c
		cell = p
		stats = s
		buffs = b

func test_damage_meta_exposes_mapped_params() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt = loaded.enums_rt
	var ds = loaded.ds

	var a_stats := OmniBuff.StatsComponent.new(5001, ds)
	var t_stats := OmniBuff.StatsComponent.new(5002, ds)
	var a_buffs := OmniBuff.BuffCore.new(ds, enums_rt)
	var t_buffs := OmniBuff.BuffCore.new(ds, enums_rt)
	var caster := UnitWithOmni.new(5001, "ally", Vector2i(2, 1), a_stats, a_buffs)
	var target := UnitWithOmni.new(5002, "enemy", Vector2i(0, 1), t_stats, t_buffs)

	var grid := Grid.new()
	grid.set_units([caster, target])
	var runtime_dict := {"stats_by_entity": {5001: a_stats, 5002: t_stats}, "buff_by_entity": {5001: a_buffs, 5002: t_buffs}}

	var r := SkillRuntime.cast("act_demo_single", caster, null, {
		"grid": grid,
		"dataset": ds,
		"enums_rt": enums_rt,
		"runtime_dict": runtime_dict,
		"turn_index": 7,
		"roll_key": 42,
		"tags": ["BASIC_ATTACK"],
		"damage_type": "PHYSICAL",
		"element": "NONE",
		"is_bonus_damage": true,
	})
	assert_true(bool(r.get("ok", false)))

	var dmg_meta := {}
	for e in r.get("effects", []):
		if String(e.get("kind","")) == "damage":
			dmg_meta = e.get("meta", {})
	assert_true(not dmg_meta.is_empty())
	assert_eq(int(dmg_meta.get("turn_index", -1)), 7)
	assert_eq(int(dmg_meta.get("roll_key", -1)), 42)
	assert_true(int(dmg_meta.get("tags_mask", 0)) != 0)
	assert_true(bool(dmg_meta.get("is_bonus_damage", false)))
```

预期：当前 meta 不包含这些字段 → FAIL

- [ ] **Step 2: 最小实现（GREEN）**

在 `OmniBuffAdapter.deal_damage` 返回 meta 中加入这些可观测字段：
- `turn_index/roll_key/tags_mask/damage_type/element/is_bonus_damage/skill_id_int/used`

- [ ] **Step 3: 验证全绿 + Commit**

```bash
git add addons/turn_skill_system/runtime/omni_buff_adapter.gd addons/turn_skill_system/tests/test_damage_pipeline_param_mapping.gd
git commit -m "fix(turn_skill_system): expose damage param mapping in meta (green)"
```

---

## Task 4: simulate_cast 在缺少 omnibuff context 时仍可跑（并给出 predicted_deltas）

**Files:**
- Create/Modify: `addons/turn_skill_system/tests/test_simulate_cast_without_omnibuff.gd`
- Modify: `addons/turn_skill_system/runtime/skill_runtime.gd`（若需要）

- [ ] **Step 1: 写 failing test（RED）**

```gdscript
extends GutTest

const SkillRuntime := preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid := preload("res://addons/turn_skill_system/runtime/grid.gd")

class U:
	extends RefCounted
	var entity_id := 1
	var camp := "ally"
	var cell := Vector2i(2, 1)
	var stats = null
	var buffs = null

func test_simulate_cast_does_not_require_omnibuff_context() -> void:
	var caster := U.new()
	var enemy := U.new()
	enemy.entity_id = 2
	enemy.camp = "enemy"
	enemy.cell = Vector2i(0, 1)
	var grid := Grid.new()
	grid.set_units([caster, enemy])

	var r := SkillRuntime.simulate_cast("act_demo_single", caster, null, {"grid": grid, "a_stats": {"ATK": 100}})
	assert_true(bool(r.get("ok", false)))
	assert_true(bool(r.get("simulation", false)))
	assert_true(r.get("predicted_deltas", []).size() >= 1)
```

- [ ] **Step 2: 最小实现（GREEN）**

如果当前 simulate 仍被某处强制要求 dataset/enums_rt/runtime_dict，则在 simulation=true 分支绕过该校验。

- [ ] **Step 3: 验证全绿 + Commit**

```bash
git add addons/turn_skill_system/runtime/skill_runtime.gd addons/turn_skill_system/tests/test_simulate_cast_without_omnibuff.gd
git commit -m "fix(turn_skill_system): allow simulate_cast without omnibuff context (green)"
```

---

## Self-Review（计划自检）
- Spec 覆盖：heal 落地、cast shape、damage 参数透传、simulate 不依赖 omnibuff → 均有对应任务与测试。
- Placeholder scan：heal 需要调用 omnibuff 内可能存在的治疗接口；若不存在则实现 heal_v1。实现时必须以仓库中 omnibuff 的 StatsComponent/Replay 能力为准（不写死未知 API）。
- 类型一致性：所有新增脚本避免 `:=`，动态值显式 `Dictionary/Array`。

