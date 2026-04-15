# Dispel & Immunity (B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 B1-B6（驱散与免疫可控性），以“单测覆盖优先”为准：补齐 4 个专门 GUT 用例文件 + rpg_tests 测试数据 + 运行时免疫/不可驱散语义补齐，使 B 全部可打勾。

**Architecture:** TDD：先补 `data/rpg_tests/buff_defs.json` 的驱散测试 buff（含 IMPLICIT/PASSIVE/undispellable/by_source），再新增 4 个 GUT 测试文件（初始应失败/或覆盖缺口），最后补齐运行时：让 `target_dispel_immunity_mask` 影响全部 dispel_*，并确保 undispellable/implicit 行为一致。全量 GUT 通过即验收。

**Tech Stack:** Godot 4.7 + GDScript + GUT。

---

## 0) 文件清单

**数据：**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dispel_by_tag.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dispel_by_source.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dispel_by_type.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_undispellable_and_immunity.gd`

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

---

## Task 1：补齐 rpg_tests 的驱散/免疫测试数据

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 新增 IMPLICIT/PASSIVE/undispellable/source-test buff**

追加以下 buff（id 全以 `buff_dispel_*` 前缀）：

1) IMPLICIT（用于 include_implicit 断言）
```json
{
  "id": "buff_dispel_implicit_atk_10",
  "name": "驱散测试：IMPLICIT ATK+10",
  "buff_type": "IMPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [{ "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 10.0 }],
  "triggers": []
}
```

2) PASSIVE（用于 include_implicit 断言）
```json
{
  "id": "buff_dispel_passive_atk_10",
  "name": "驱散测试：PASSIVE ATK+10",
  "buff_type": "PASSIVE",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [{ "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 10.0 }],
  "triggers": []
}
```

3) 不可驱散（undispellable=true）
```json
{
  "id": "buff_dispel_undispellable_atk_10",
  "name": "驱散测试：不可驱散 ATK+10",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "dispel": { "dispellable": false },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [{ "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 10.0 }],
  "triggers": []
}
```

4) 按来源拆分（BY_SOURCE_INSTANCE）用于 dispel_by_source
```json
{
  "id": "buff_dispel_source_mark",
  "name": "驱散测试：按来源拆分 DEF+5",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "ADD_STACK", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "BY_SOURCE_INSTANCE" },
  "effects": [{ "kind": "modifier", "stat": "DEF", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 5.0 }],
  "triggers": []
}
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/data/rpg_tests/buff_defs.json
git commit -m "test(data): add dispel/immune fixtures"
```

---

## Task 2：新增单测 B1+B6（dispel_by_tag + include_implicit + DOT清理）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dispel_by_tag.gd`

- [ ] **Step 1: 写测试**

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

func test_dispel_by_tag_debuff_clears_dot_instances() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()
	var turn = OmniTurnComponent.new()

	var attacker = TestBattle.make_entity(7601, ds, enums_rt)
	var defender = TestBattle.make_entity(7602, ds, enums_rt)
	var runtime = TestBattle.make_runtime([attacker, defender])
	var ids = PackedInt32Array([7601, 7602]); ids.sort()
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 让 attacker 触发 AFTER_DEAL 挂 DOT
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_apply_dot", 7601)
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 12.0, replay, 1, tags_mask, runtime)
	assert_eq(_count_by_id(defender.buffs, ds, "buff_dot_fire_3t"), 1)

	# TurnStart tick 一次，确认会产生 trace
	var before = replay.dot_traces.size()
	turn.on_turn_start(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, replay)
	assert_eq(replay.dot_traces.size() - before, 1)

	# 驱散 DEBUFF：应移除 DOT，且后续 tick 不再产生 trace
	var removed: int = int(defender.buffs.dispel_by_tag(defender.stats, "DEBUFF", false))
	assert_eq(removed, 1)
	assert_eq(_count_by_id(defender.buffs, ds, "buff_dot_fire_3t"), 0)

	before = replay.dot_traces.size()
	turn.on_turn_start(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, replay)
	assert_eq(replay.dot_traces.size() - before, 0)

func test_dispel_by_tag_include_implicit_false_keeps_implicit_and_passive() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7603, ds, enums_rt)

	e.buffs.apply_buff(e.stats, "buff_dispel_implicit_atk_10", 1)
	e.buffs.apply_buff(e.stats, "buff_dispel_passive_atk_10", 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_implicit_atk_10"), 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_passive_atk_10"), 1)

	var removed: int = int(e.buffs.dispel_by_tag(e.stats, "BUFF", false))
	assert_eq(removed, 0)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_implicit_atk_10"), 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_passive_atk_10"), 1)

func test_dispel_by_tag_include_implicit_true_removes_implicit_and_passive() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7604, ds, enums_rt)

	e.buffs.apply_buff(e.stats, "buff_dispel_implicit_atk_10", 1)
	e.buffs.apply_buff(e.stats, "buff_dispel_passive_atk_10", 1)

	var removed: int = int(e.buffs.dispel_by_tag(e.stats, "BUFF", true))
	assert_eq(removed, 2)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_implicit_atk_10"), 0)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_passive_atk_10"), 0)
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/addons/omnibuff/tests/rpg/test_dispel_by_tag.gd
git commit -m "test(b): add dispel_by_tag tests"
```

---

## Task 3：新增单测 B2（dispel_by_source）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dispel_by_source.gd`

- [ ] **Step 1: 写测试（同 buff_id 不同 source 的实例，仅驱散某一来源）**

```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func _count(buffs: OmniBuffCore, ds: OmniCompiledDataset, buff_id_str: String) -> int:
	var n := 0
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		if String(ds.buff_defs[int(inst.buff_def_id)].get("id","")) == buff_id_str:
			n += 1
	return n

func test_dispel_by_source_removes_only_that_source() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7610, ds, enums_rt)

	# 同一个 buff_id，来源 1001 与 2002 各施加一次
	e.buffs.apply_buff(e.stats, "buff_dispel_source_mark", 1001)
	e.buffs.apply_buff(e.stats, "buff_dispel_source_mark", 2002)
	assert_eq(_count(e.buffs, ds, "buff_dispel_source_mark"), 2)

	var def_id := ds.stat_id("DEF")
	assert_eq(float(e.stats.get_final(def_id)), 5.0 + 5.0 + 5.0)

	var removed: int = int(e.buffs.dispel_by_source(e.stats, 1001, false))
	assert_eq(removed, 1)
	assert_eq(_count(e.buffs, ds, "buff_dispel_source_mark"), 1)
	assert_eq(float(e.stats.get_final(def_id)), 5.0 + 5.0)
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/addons/omnibuff/tests/rpg/test_dispel_by_source.gd
git commit -m "test(b): add dispel_by_source tests"
```

---

## Task 4：新增单测 B3（dispel_by_type）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dispel_by_type.gd`

- [ ] **Step 1: 写测试（仅移除 EXPLICIT；IMPLICIT/PASSIVE 保留）**

```gdscript
extends GutTest
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func _count(buffs: OmniBuffCore) -> int:
	return int(buffs.inst_ids.size())

func test_dispel_by_type_explicit_only() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7620, ds, enums_rt)

	e.buffs.apply_buff(e.stats, "buff_life_replace_atk_10_2t", 1)         # EXPLICIT
	e.buffs.apply_buff(e.stats, "buff_dispel_implicit_atk_10", 1)         # IMPLICIT
	e.buffs.apply_buff(e.stats, "buff_dispel_passive_atk_10", 1)          # PASSIVE

	assert_eq(_count(e.buffs), 3)
	var removed: int = int(e.buffs.dispel_by_type(e.stats, "EXPLICIT"))
	assert_eq(removed, 1)
	assert_eq(_count(e.buffs), 2)
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/addons/omnibuff/tests/rpg/test_dispel_by_type.gd
git commit -m "test(b): add dispel_by_type tests"
```

---

## Task 5：新增单测 B4+B5（undispellable + immunity 影响全部 dispel_*）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_undispellable_and_immunity.gd`

- [ ] **Step 1: undispellable 不可被 dispel_* 移除**
- [ ] **Step 2: immunity 阻止 dispel_by_tag/source/type**

（略，按 spec 写两个用例：一个验证 undispellable，另一个设置 target_dispel_immunity_mask 后对三种 dispel 都返回 0）

- [ ] **Step 3: 提交**

```bash
git add godot-buff/addons/omnibuff/tests/rpg/test_undispellable_and_immunity.gd
git commit -m "test(b): add undispellable + immunity tests"
```

---

## Task 6：运行时补齐（免疫影响全部 dispel_*）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 在 dispel_by_source/type 增加免疫检查**
- [ ] **Step 2: 跑全量 GUT，修到全绿**
- [ ] **Step 3: 提交**

```bash
git add godot-buff/addons/omnibuff/runtime/core/buff_core.gd
git commit -m "feat(b): apply dispel immunity to all dispel methods"
```

