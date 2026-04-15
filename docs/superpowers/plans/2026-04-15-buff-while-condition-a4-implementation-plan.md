# Buff While-Condition (A4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地 A4（WHILE_CONDITION）v1：支持 `STAT_THRESHOLD` 条件，并采用“路线 A：挂起/恢复（active/inactive）”。条件不满足时不删除实例，而是撤销 modifiers/事件监听并暂停 DOT tick；条件恢复时重建 modifiers/监听并恢复 DOT tick；同时保证非 DOT 的到期仍会推进并能到期移除（避免变成永久）。

**Architecture:** TDD：先在 `data/rpg_tests` 增加一个最小条件 buff（HP<=50 时 ATK+10），再新增 GUT 用例验证：初始不生效→扣血到阈值→下一次 tick 生效→回血→下一次 tick 失效；再补一个“到期仍推进”的用例（inactive 也会到期）。实现上在 `BuffCore.BuffInst` 增加 `active` 字段，并在 turn tick 中评估条件切换，提供 `_activate/_deactivate` 重建/撤销效果；DOT tick 处按 owner_buff_inst_id 查 BuffInst.active 决定是否跳伤。

**Tech Stack:** Godot 4.7 + GDScript + GUT + data/rpg_tests。

---

## 0) 文件清单

**数据：**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_while_condition.gd`

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

---

## Task 1：在 rpg_tests 增加最小条件 buff

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 新增 buff_cond_hp_le_50_atk_up_10**

```json
{
  "id": "buff_cond_hp_le_50_atk_up_10",
  "name": "条件：HP<=50 时 ATK+10",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "GLOBAL" },
  "conditions": [
    { "condition_type": "STAT_THRESHOLD", "stat": "HP", "op": "LE", "value": 50.0 }
  ],
  "effects": [
    { "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 10.0 }
  ],
  "triggers": []
}
```

- [ ] **Step 2（可选但建议）: 新增一个会到期的条件 buff（用于证明 inactive 也会到期）**

```json
{
  "id": "buff_cond_hp_le_50_atk_up_10_2t",
  "name": "条件：HP<=50 时 ATK+10（2回合到期）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "TURNS", "turns": 2, "tick_phase": "TURN_END" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "GLOBAL" },
  "conditions": [
    { "condition_type": "STAT_THRESHOLD", "stat": "HP", "op": "LE", "value": 50.0 }
  ],
  "effects": [
    { "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 10.0 }
  ],
  "triggers": []
}
```

- [ ] **Step 3: 提交**

```bash
git add godot-buff/data/rpg_tests/buff_defs.json
git commit -m "test(data): add while-condition (STAT_THRESHOLD) buffs"
```

---

## Task 2：新增 GUT 用例（条件生效/失效 + 到期推进）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_while_condition.gd`

- [ ] **Step 1: 编写 failing test：初始 inactive，阈值后 active，回血后 inactive**

```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_while_condition_hp_threshold_toggles_active() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var pipe = OmniDamagePipeline.new()
	var turn = OmniTurnComponent.new()

	var eid = 7401
	var e = TestBattle.make_entity(eid, ds, enums_rt)
	var runtime = TestBattle.make_runtime([e])
	var ids = PackedInt32Array([eid]); ids.sort()

	var hp_id := ds.stat_id("HP")
	var atk_id := ds.stat_id("ATK")

	# 初始 HP=100，施加后应 inactive（ATK 不变）
	e.buffs.apply_buff(e.stats, "buff_cond_hp_le_50_atk_up_10", 111)
	assert_eq(float(e.stats.get_final(atk_id)), 10.0)

	# 扣血到 50，下一次 tick 后应 active（ATK +10）
	e.stats.add_base(hp_id, -50.0)
	turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null)
	assert_eq(float(e.stats.get_final(atk_id)), 20.0)

	# 回血到 60，下一次 tick 后应 inactive（ATK 回退）
	e.stats.add_base(hp_id, 10.0)
	turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null)
	assert_eq(float(e.stats.get_final(atk_id)), 10.0)
```

- [ ] **Step 2:（可选）到期推进用例：inactive 也会到期**

```gdscript
func test_while_condition_inactive_still_expires() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var pipe = OmniDamagePipeline.new()
	var turn = OmniTurnComponent.new()

	var eid = 7402
	var e = TestBattle.make_entity(eid, ds, enums_rt)
	var runtime = TestBattle.make_runtime([e])
	var ids = PackedInt32Array([eid]); ids.sort()

	# 初始 HP=100（条件不满足），但 buff 是 2 回合到期
	e.buffs.apply_buff(e.stats, "buff_cond_hp_le_50_atk_up_10_2t", 111)
	assert_eq(e.buffs.inst_ids.size(), 1)

	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null) # 2->1
	assert_eq(e.buffs.inst_ids.size(), 1)
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null) # 1->0 到期
	assert_eq(e.buffs.inst_ids.size(), 0)
```

- [ ] **Step 3: 提交 failing tests**

```bash
git add godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_while_condition.gd
git commit -m "test(lifecycle): add while-condition (STAT_THRESHOLD) tests"
```

---

## Task 3：运行时实现（BuffInst.active + 条件评估 + 挂起/恢复）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: BuffInst 增加 active 字段**

在 `class BuffInst` 增加：
```gdscript
var active: bool = true
```

- [ ] **Step 2: 实现条件评估（STAT_THRESHOLD）**

新增函数：
```gdscript
func _conditions_satisfied(stats: OmniStatsComponent, def: Dictionary) -> bool:
	var conds: Array = def.get("conditions", [])
	if conds.is_empty():
		return true
	for c in conds:
		if String(c.get("condition_type","")) != "STAT_THRESHOLD":
			continue
		var stat_id := ds.stat_id(String(c.get("stat","")))
		if stat_id < 0:
			continue
		var op := String(c.get("op","LE"))
		var rhs := float(c.get("value", 0.0))
		var lhs := float(stats.get_final(stat_id))
		var ok := true
		match op:
			"LE": ok = lhs <= rhs
			"LT": ok = lhs < rhs
			"GE": ok = lhs >= rhs
			"GT": ok = lhs > rhs
			_: ok = true
		if not ok:
			return false
	return true
```

- [ ] **Step 3: 实现 deactivate/activate**

新增：
```gdscript
func _deactivate_instance(stats: OmniStatsComponent, inst: BuffInst) -> void:
	# 撤销 modifiers
	for mr in inst.modifier_refs:
		var stat_id := int(mr.stat_id)
		var list: Array = stats.core.modifiers_by_stat[stat_id]
		var kept: Array = []
		for x in list:
			if int(x.source_inst_id) != int(inst.inst_id):
				kept.append(x)
		stats.core.modifiers_by_stat[stat_id] = kept
		stats.core.mark_dirty(stat_id)
	inst.modifier_refs.clear()
	# 注销事件监听
	_unregister_listeners_for_inst(inst.inst_id)
	inst.active = false

func _activate_instance(stats: OmniStatsComponent, inst: BuffInst, def: Dictionary) -> void:
	# 重建 modifiers（复用 _rebuild_instance_modifiers）
	_rebuild_instance_modifiers(stats, inst.inst_id)
	# 重建 triggers（可抽取 _register_triggers_for_instance）
	_register_triggers_for_instance(inst, def)
	inst.active = true
```

> 注意：`_register_triggers_for_instance` 可从现有 `apply_buff` 里抽取出来，避免复制逻辑。

- [ ] **Step 4: 在 apply_buff 创建新实例后立即评估一次条件**

若条件不满足：
- 调用 `_deactivate_instance(stats, inst)`（但保留实例在 instances_by_id/inst_ids 中）

- [ ] **Step 5: 在 turn tick 中评估状态切换**

在 `on_turn_start` 与 `on_turn_end`（或统一内部函数）中：
- 取 owner_stats（`stats_by_entity[owner_entity_id]`）
- 遍历 `inst_ids.duplicate()`，对每个 inst：
  - want_active = _conditions_satisfied(owner_stats, def)
  - 若 want_active != inst.active：切换

- [ ] **Step 6: DOT tick 与 active 联动（暂停）**

在 `_tick_dots` 的循环里，在结算前插入：
```gdscript
var owner_inst: BuffInst = instances_by_id.get(int(d.owner_buff_inst_id), null)
if owner_inst == null or (not owner_inst.active):
	kept.append(d)
	continue
```

- [ ] **Step 7: 跑全量 GUT tests，修到全绿**

重点：
- `test_buff_lifecycle_while_condition.gd`
- 现有整回合脚本测试、DOT 测试不回归

- [ ] **Step 8: 提交实现**

```bash
git add godot-buff/addons/omnibuff/runtime/core/buff_core.gd
git commit -m "feat(lifecycle): add while-condition STAT_THRESHOLD with suspend/resume"
```

