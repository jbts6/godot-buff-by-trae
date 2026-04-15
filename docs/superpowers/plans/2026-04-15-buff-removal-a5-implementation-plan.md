# Buff Removal (A5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 A5 第一档：新增 `remove_by_*` 主动移除 API（按 buff_id/tag/source），并通过 GUT 锁死“移除后属性回退、事件不再触发、DOT 不再 tick、inactive 也可移除”的不变量。

**Architecture:** 先加 failing tests（基于 rpg_tests 数据集）→ 再在 `BuffCore` 中实现 `remove_by_buff_id/remove_by_tag/remove_by_source`（内部统一走 `remove_by_instance`，遍历 `inst_ids.duplicate()` 保证稳定）→ 跑全套 GUT → 提交。

**Tech Stack:** Godot 4.7 + GDScript + GUT。

---

## 0) 文件清单

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_buff_removal_a5.gd`

---

## Task 1：写 failing tests（A5 不变量）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_buff_removal_a5.gd`

- [ ] **Step 1: 创建测试文件**

```gdscript
extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func _count_by_id(buffs: OmniBuffCore, ds: OmniCompiledDataset, buff_id_str: String) -> int:
	var n := 0
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		if String(ds.buff_defs[int(inst.buff_def_id)].get("id","")) == buff_id_str:
			n += 1
	return n

func test_remove_by_buff_id_reverts_stats() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7501, ds, enums_rt)

	var atk_id := ds.stat_id("ATK")
	e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3", 111) # ATK +10
	assert_eq(float(e.stats.get_final(atk_id)), 20.0)

	var removed: int = int(e.buffs.remove_by_buff_id(e.stats, "buff_life_stack_atk_10_2t_max3", "ALL"))
	assert_eq(removed, 1)
	assert_eq(float(e.stats.get_final(atk_id)), 10.0)

func test_remove_by_tag_removes_all_debuff() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7502, ds, enums_rt)

	# rpg_tests 里已有 debuff：buff_dot_fire_3t（tags: DEBUFF/DOT/FIRE）
	e.buffs.apply_buff(e.stats, "buff_dot_fire_3t", 111)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dot_fire_3t"), 1)

	var removed: int = int(e.buffs.remove_by_tag(e.stats, "DEBUFF", "ALL"))
	assert_eq(removed, 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dot_fire_3t"), 0)

func test_remove_by_buff_id_stops_event_trigger() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()

	var attacker := TestBattle.make_entity(7503, ds, enums_rt)
	var defender := TestBattle.make_entity(7504, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# attacker 挂 AFTER_DEAL -> APPLY_BUFF(DOT)
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_apply_dot", 7503)

	# 打一段：应挂 DOT
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 12.0, replay, 1, tags_mask, runtime)
	assert_eq(_count_by_id(defender.buffs, ds, "buff_dot_fire_3t"), 1)

	# 移除 attacker 的触发 buff，再打：不应再挂 DOT
	var removed: int = int(attacker.buffs.remove_by_buff_id(attacker.stats, "buff_on_hit_apply_dot", "ALL"))
	assert_eq(removed, 1)
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 12.0, replay, 2, tags_mask, runtime)
	assert_eq(_count_by_id(defender.buffs, ds, "buff_dot_fire_3t"), 1)

func test_remove_inactive_instance_works() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7505, ds, enums_rt)

	var hp_id := ds.stat_id("HP")
	var atk_id := ds.stat_id("ATK")
	# 初始 HP=100，不满足 HP<=50，实例会 inactive
	e.buffs.apply_buff(e.stats, "buff_cond_hp_le_50_atk_up_10", 111)
	assert_eq(float(e.stats.get_final(atk_id)), 10.0)
	assert_eq(_count_by_id(e.buffs, ds, "buff_cond_hp_le_50_atk_up_10"), 1)

	var removed: int = int(e.buffs.remove_by_buff_id(e.stats, "buff_cond_hp_le_50_atk_up_10", "ALL"))
	assert_eq(removed, 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_cond_hp_le_50_atk_up_10"), 0)

	# 扣血到 50 也不应再“复活”该 buff
	e.stats.add_base(hp_id, -50.0)
	assert_eq(float(e.stats.get_final(atk_id)), 10.0)
```

- [ ] **Step 2: 提交 failing tests**

```bash
git add godot-buff/addons/omnibuff/tests/rpg/test_buff_removal_a5.gd
git commit -m "test(a5): add buff removal invariants tests"
```

---

## Task 2：实现 remove_by_* API

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 在 BuffCore 增加 remove_by_buff_id**

```gdscript
func remove_by_buff_id(stats: OmniStatsComponent, buff_id_str: String, scope: String = "ALL", source_entity_id: int = -1, include_implicit: bool = false, force: bool = false) -> int:
	var bdid := ds.buff_id(buff_id_str)
	if bdid < 0:
		return 0
	var removed := 0
	for inst_id in inst_ids.duplicate():
		var inst: BuffInst = instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		if inst.buff_def_id != bdid:
			continue
		if source_entity_id >= 0 and int(inst.source_entity_id) != source_entity_id:
			continue
		if (not include_implicit) and (inst.buff_type == "IMPLICIT" or inst.buff_type == "PASSIVE"):
			continue
		if (not force) and inst.undispellable:
			continue
		if remove_by_instance(stats, int(inst.inst_id), true):
			removed += 1
			if scope == "FIRST":
				break
	return removed
```

- [ ] **Step 2: 实现 remove_by_tag / remove_by_source**

> 复用 `enums_rt.tag_mask` 与实例字段过滤，遍历 `inst_ids.duplicate()`，内部调用 `remove_by_instance(...)`。

- [ ] **Step 3: 跑全量 GUT tests，修到全绿**

- [ ] **Step 4: 提交实现**

```bash
git add godot-buff/addons/omnibuff/runtime/core/buff_core.gd
git commit -m "feat(a5): add remove_by_* APIs for buff cleanup"
```

