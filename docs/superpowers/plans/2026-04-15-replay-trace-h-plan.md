# Replay/Trace (H1~H3 Minimal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 通过新增专门 GUT 测试把 H1~H3（DamageTrace/DotTrace 完整 + Debug dump 可读）收尾到可打勾，并同步更新 checklist。

**Architecture:** 不改战斗逻辑；优先写 3 个 failing tests 来锁死追帧结构与 dump 输出；如发现 replay.gd 字段缺失/输出不稳定再做最小修复；最后更新 checklist 勾选 H1~H3。

**Tech Stack:** Godot 4.7 + GDScript + GUT。

---

## 0) 文件清单

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_replay_damage_trace_fields.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_replay_dot_trace_fields.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_replay_debug_dump_range.gd`

**可能的修复（视测试失败情况而定）：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/replay.gd`

**文档：**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

---

## Task 1：新增测试（H1 DamageTrace 字段完整）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_replay_damage_trace_fields.gd`

- [ ] **Step 1: 写 failing test**

```gdscript
extends GutTest

const ReplayScript = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_damage_trace_fields_are_present() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()

	var a = TestBattle.make_entity(8301, ds, enums_rt)
	var d = TestBattle.make_entity(8302, ds, enums_rt)
	var runtime = TestBattle.make_runtime([a, d])

	# 固定命中/暴击，避免随机分支
	a.stats.add_base(ds.stat_id("HIT_RATE"), 1.0 - float(a.stats.get_final(ds.stat_id("HIT_RATE"))))
	a.stats.add_base(ds.stat_id("CRIT_RATE"), 0.0 - float(a.stats.get_final(ds.stat_id("CRIT_RATE"))))
	d.stats.add_base(ds.stat_id("EVADE"), 0.0 - float(d.stats.get_final(ds.stat_id("EVADE"))))

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 10.0, replay, 1, tags_mask, runtime)

	assert_eq(replay.damage_traces.size(), 1)
	var t = replay.damage_traces[0]

	assert_true(typeof(t.turn) == TYPE_INT)
	assert_true(typeof(t.attacker_id) == TYPE_INT)
	assert_true(typeof(t.defender_id) == TYPE_INT)
	assert_true(typeof(t.hit) == TYPE_BOOL)
	assert_true(typeof(t.crit) == TYPE_BOOL)
	assert_true(typeof(t.base_damage) == TYPE_FLOAT)
	assert_true(typeof(t.final_damage) == TYPE_FLOAT)
	assert_true(typeof(t.tags_mask) == TYPE_INT)
	assert_true(typeof(t.triggered_inst_ids) == TYPE_PACKED_INT32_ARRAY)
	assert_true(typeof(t.stage_triggers) == TYPE_DICTIONARY)
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_replay_damage_trace_fields.gd
git -C godot-buff commit -m "test(h1): lock DamageTrace schema"
```

---

## Task 2：新增测试（H2 DotTrace 字段完整）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_replay_dot_trace_fields.gd`

- [ ] **Step 1: 写 failing test**

```gdscript
extends GutTest

const ReplayScript = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const TurnComponent = preload("res://addons/omnibuff/runtime/components/turn_component.gd")

func test_dot_trace_fields_are_present() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()
	var turn = TurnComponent.new()

	var src = TestBattle.make_entity(8311, ds, enums_rt)
	var tgt = TestBattle.make_entity(8312, ds, enums_rt)
	var runtime = TestBattle.make_runtime([src, tgt])

	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", 8311)
	var ids := PackedInt32Array([8311, 8312]); ids.sort()
	turn.on_turn_start(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, replay)

	assert_true(replay.dot_traces.size() >= 1)
	var t = replay.dot_traces[replay.dot_traces.size() - 1]

	assert_true(typeof(t.turn) == TYPE_INT)
	assert_true(typeof(t.dot_inst_id) == TYPE_INT)
	assert_true(typeof(t.owner_buff_inst_id) == TYPE_INT)
	assert_true(typeof(t.source_entity_id) == TYPE_INT)
	assert_true(typeof(t.target_entity_id) == TYPE_INT)
	assert_true(typeof(t.read_source_stat) == TYPE_STRING)
	assert_true(typeof(t.source_stat_value) == TYPE_FLOAT)
	assert_true(typeof(t.base_ratio) == TYPE_FLOAT)
	assert_true(typeof(t.base_damage) == TYPE_FLOAT)
	assert_true(typeof(t.final_damage) == TYPE_FLOAT)
	assert_true(typeof(t.tags_mask) == TYPE_INT)
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_replay_dot_trace_fields.gd
git -C godot-buff commit -m "test(h2): lock DotTrace schema"
```

---

## Task 3：新增测试（H3 debug dump range 可读）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_replay_debug_dump_range.gd`

- [ ] **Step 1: 写 failing test**

```gdscript
extends GutTest

const ReplayScript = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const TurnComponent = preload("res://addons/omnibuff/runtime/components/turn_component.gd")

func test_debug_dump_ranges_are_readable() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()
	var turn = TurnComponent.new()

	var a = TestBattle.make_entity(8321, ds, enums_rt)
	var d = TestBattle.make_entity(8322, ds, enums_rt)
	var runtime = TestBattle.make_runtime([a, d])

	# 产生两条 damage trace（两次调用）
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 10.0, replay, 1, tags_mask, runtime)
	pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 10.0, replay, 1, tags_mask, runtime)
	assert_true(replay.damage_traces.size() >= 2)

	# 产生 dot trace
	d.buffs.apply_buff(d.stats, "buff_dot_fire_3t", 8321)
	var ids := PackedInt32Array([8321, 8322]); ids.sort()
	turn.on_turn_start(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, replay)
	assert_true(replay.dot_traces.size() >= 1)

	var s1: String = replay.debug_dump_damage_range(replay.damage_traces.size() - 2)
	assert_true(s1.find("[DamageTrace]") >= 0)
	assert_true(s1.find("turn=") >= 0)
	assert_true(s1.find("base=") >= 0)
	assert_true(s1.find("final=") >= 0)

	var s2: String = replay.debug_dump_dot_range(replay.dot_traces.size() - 1)
	assert_true(s2.find("[DotTrace]") >= 0)
	assert_true(s2.find("turn=") >= 0)
	assert_true(s2.find("src=") >= 0)
	assert_true(s2.find("tgt=") >= 0)
	assert_true(s2.find("base=") >= 0)
	assert_true(s2.find("final=") >= 0)
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_replay_debug_dump_range.gd
git -C godot-buff commit -m "test(h3): lock replay debug dump readability"
```

---

## Task 4：如有需要，最小修复 replay.gd（仅当测试失败）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/replay.gd`

- [ ] **Step 1: 修复并提交**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/replay.gd
git -C godot-buff commit -m "fix(h): stabilize replay traces/dumps"
```

---

## Task 5：更新 checklist 勾选 H1~H3

**Files:**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

- [ ] **Step 1: 勾选为 [x]**
- [ ] **Step 2: 提交**

```bash
git -C godot-buff add docs/superpowers/checklists/omnibuff-done-definition.md
git -C godot-buff commit -m "docs(checklist): mark H complete"
```

