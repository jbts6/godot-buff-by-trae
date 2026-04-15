# Buff Lifecycle (A1+A3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 OmniBuff 中落地生命周期第一档：A1（叠加：REPLACE/ADD_STACK/MULTI_INSTANCE + ownership_mode/max_stack）+ A3（非 DOT 的 TURNS 到期移除，支持 duration.tick_phase=TURN_START/TURN_END），并用 GUT 测试锁死行为，保证可回归。

**Architecture:** 采用 TDD：先在 `data/rpg_tests` 增加生命周期专用 buff，再新增 GUT 用例（REPLACE/ADD_STACK/MULTI_INSTANCE/到期），使其在当前版本失败；随后修改 `BuffCore.apply_buff` 实现 ownership-key 查找与叠加语义，并在 `BuffCore.on_turn_start/on_turn_end` 中增加“非 DOT 的到期推进”逻辑（按 tick_phase 递减 remaining_turns、到期移除），最后让全套 tests 全绿。

**Tech Stack:** Godot 4.7 + GDScript + GUT + data/rpg_tests。

---

## 0) 文件清单

**数据：**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_stacking.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_expire.gd`

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

---

## Task 1：为生命周期测试扩展 rpg_tests/buff_defs.json

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 添加 4 个生命周期专用 buff**

在 `buff_defs.json` 增加以下定义（建议放在文件末尾，避免影响已有 id 的可读性）：

1) `buff_life_replace_atk_10_2t`（REPLACE / GLOBAL / turns=2 / tick_phase=TURN_END）
```json
{
  "id": "buff_life_replace_atk_10_2t",
  "name": "生命周期：REPLACE ATK+10（2回合）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "TURNS", "turns": 2, "tick_phase": "TURN_END" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 10.0 }
  ],
  "triggers": []
}
```

2) `buff_life_stack_atk_10_2t_max3`（ADD_STACK / GLOBAL / turns=2 / max_stack=3）
```json
{
  "id": "buff_life_stack_atk_10_2t_max3",
  "name": "生命周期：ADD_STACK ATK+10（2回合，最多3层）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "TURNS", "turns": 2, "tick_phase": "TURN_END" },
  "stack": { "mode": "ADD_STACK", "max_stack": 3, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 10.0 }
  ],
  "triggers": []
}
```

3) `buff_life_multi_atk_10_2t`（MULTI_INSTANCE / turns=2）
```json
{
  "id": "buff_life_multi_atk_10_2t",
  "name": "生命周期：MULTI_INSTANCE ATK+10（2回合）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "TURNS", "turns": 2, "tick_phase": "TURN_END" },
  "stack": { "mode": "MULTI_INSTANCE", "max_stack": 99, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 10.0 }
  ],
  "triggers": []
}
```

4) `buff_life_stack_by_source_def_5_2t_max2`（ADD_STACK / BY_SOURCE_INSTANCE / DEF +5 / turns=2 / max_stack=2）
```json
{
  "id": "buff_life_stack_by_source_def_5_2t_max2",
  "name": "生命周期：按来源叠层 DEF+5（2回合，最多2层/来源）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "TURNS", "turns": 2, "tick_phase": "TURN_END" },
  "stack": { "mode": "ADD_STACK", "max_stack": 2, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "BY_SOURCE_INSTANCE" },
  "effects": [
    { "kind": "modifier", "stat": "DEF", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 5.0 }
  ],
  "triggers": []
}
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/data/rpg_tests/buff_defs.json
git commit -m "test(data): add lifecycle buffs for stacking/expiry tests"
```

---

## Task 2：新增生命周期用例（叠加：REPLACE/ADD_STACK/MULTI_INSTANCE/ownership）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_stacking.gd`

- [ ] **Step 1: 编写 failing tests**

```gdscript
extends GutTest

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

func test_replace_global_keeps_one_instance() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var e := TestBattle.make_entity(7101, ds, enums_rt)
	e.buffs.apply_buff(e.stats, "buff_life_replace_atk_10_2t", 111)
	e.buffs.apply_buff(e.stats, "buff_life_replace_atk_10_2t", 222)
	assert_eq(_count_by_id(e.buffs, ds, "buff_life_replace_atk_10_2t"), 1)

func test_add_stack_global_increases_stacks_and_caps() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var e := TestBattle.make_entity(7102, ds, enums_rt)
	for i in range(5):
		e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3", 111)
	assert_eq(_count_by_id(e.buffs, ds, "buff_life_stack_atk_10_2t_max3"), 1)
	# stacks 应被 cap 到 3
	var inst_id := int(e.buffs.inst_ids[0])
	var inst = e.buffs.instances_by_id[inst_id]
	assert_eq(int(inst.stacks), 3)
	# ATK: (10 base + 10*3) = 40
	assert_eq(float(e.stats.get_final(ds.stat_id("ATK"))), 40.0)

func test_multi_instance_creates_three_instances() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var e := TestBattle.make_entity(7103, ds, enums_rt)
	for i in range(3):
		e.buffs.apply_buff(e.stats, "buff_life_multi_atk_10_2t", 111)
	assert_eq(_count_by_id(e.buffs, ds, "buff_life_multi_atk_10_2t"), 3)
	# ATK: (10 base + 10*3) = 40
	assert_eq(float(e.stats.get_final(ds.stat_id("ATK"))), 40.0)

func test_add_stack_by_source_creates_two_owner_instances() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var e := TestBattle.make_entity(7104, ds, enums_rt)
	# source 1001 叠两层（max2）
	e.buffs.apply_buff(e.stats, "buff_life_stack_by_source_def_5_2t_max2", 1001)
	e.buffs.apply_buff(e.stats, "buff_life_stack_by_source_def_5_2t_max2", 1001)
	# source 2002 叠一层
	e.buffs.apply_buff(e.stats, "buff_life_stack_by_source_def_5_2t_max2", 2002)

	# 期望：存在 2 个实例（按来源拆分），DEF = 5 base + (5*2 + 5*1) = 20
	assert_eq(_count_by_id(e.buffs, ds, "buff_life_stack_by_source_def_5_2t_max2"), 2)
	assert_eq(float(e.stats.get_final(ds.stat_id("DEF"))), 20.0)
```

- [ ] **Step 2: 在 GUT 里运行该脚本，确认失败（当前未实现叠加语义）**

- [ ] **Step 3: 提交 failing tests**

```bash
git add godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_stacking.gd
git commit -m "test(lifecycle): add stacking tests (REPLACE/ADD_STACK/MULTI_INSTANCE)"
```

---

## Task 3：新增生命周期用例（非 DOT 的 TURNS 到期）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_expire.gd`

- [ ] **Step 1: 编写 failing test（tick_phase=TURN_END，2次 TurnEnd 后到期）**

```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_turns_buff_expires_on_turn_end() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var pipe := OmniDamagePipeline.new()
	var turn := OmniTurnComponent.new()

	var eid := 7201
	var e := TestBattle.make_entity(eid, ds, enums_rt)
	var runtime := TestBattle.make_runtime([e])
	var ids := PackedInt32Array([eid]); ids.sort()

	e.buffs.apply_buff(e.stats, "buff_life_replace_atk_10_2t", 111)
	assert_eq(float(e.stats.get_final(ds.stat_id("ATK"))), 20.0)

	# Turn1 end：remaining_turns 2->1，仍有效
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null)
	assert_eq(float(e.stats.get_final(ds.stat_id("ATK"))), 20.0)

	# Turn2 end：remaining_turns 1->0，到期移除
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null)
	assert_eq(float(e.stats.get_final(ds.stat_id("ATK"))), 10.0)
```

- [ ] **Step 2: 提交 failing test**

```bash
git add godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_expire.gd
git commit -m "test(lifecycle): add non-dot turns expiry test"
```

---

## Task 4：实现 A1（叠加）+ A3（非DOT到期）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 为 BuffInst 增加 ownership_key 字段**

在 `class BuffInst` 增加：
```gdscript
var ownership_key: int
```
用于查找/替换/叠层。

- [ ] **Step 2: 在 BuffCore 增加 lookup 表**

在 BuffCore 成员增加：
```gdscript
var inst_id_by_ownership: Dictionary = {} # ownership_key -> inst_id
```

ownership_key 计算：
```gdscript
static func _ownership_key(bdid: int, ownership_mode: String, source_entity_id: int) -> int:
	var k := 0
	if ownership_mode == "BY_SOURCE_INSTANCE":
		k = source_entity_id
	return (bdid << 16) ^ (k & 0xffff)
```
（注意：这是最小实现；若 entity_id 可能 > 65535，后续可改为字符串 key。）

- [ ] **Step 3: 改造 apply_buff 实现三种 stack.mode**

伪代码（需落地为实际 GDScript）：
```gdscript
var stack: Dictionary = ds.buff_defs[bdid].get("stack", {})
var mode := String(stack.get("mode","REPLACE"))
var max_stack := int(stack.get("max_stack", 1))
var ownership_mode := String(stack.get("ownership_mode","GLOBAL"))

if mode == "MULTI_INSTANCE":
	return _create_new_instance(...)

var key := _ownership_key(bdid, ownership_mode, source_entity_id)
var old_inst_id := int(inst_id_by_ownership.get(key, -1))

if old_inst_id < 0:
	var new_id := _create_new_instance(...)
	instances_by_id[new_id].ownership_key = key
	inst_id_by_ownership[key] = new_id
	return new_id

var old_inst: BuffInst = instances_by_id.get(old_inst_id, null)
if old_inst == null:
	inst_id_by_ownership.erase(key)
	return apply_buff(stats, buff_id_str, source_entity_id) # 递归一次（最小恢复）

if mode == "REPLACE":
	remove_by_instance(stats, old_inst_id, true)
	var new_id := _create_new_instance(...)
	instances_by_id[new_id].ownership_key = key
	inst_id_by_ownership[key] = new_id
	return new_id

if mode == "ADD_STACK":
	old_inst.stacks = min(old_inst.stacks + 1, max_stack)
	# 最小刷新语义：重置 remaining_turns
	old_inst.remaining_turns = int(ds.buff_defs[bdid].get("duration", {}).get("turns", -1))
	# 重建该实例注入的 modifiers（让数值随 stacks 生效）
	_rebuild_instance_modifiers(stats, old_inst_id)
	return old_inst_id
```

其中 `_create_new_instance` 是把现在 apply_buff 中“创建 inst + 注入 effects/triggers + 创建 dot”抽出来的函数；
`_rebuild_instance_modifiers` 做：
- 先 remove_by_instance 的“撤销 modifiers”逻辑的子集（只撤销 modifier_refs，不移除实例）
- 再按 stacks 重新注入（例如 value * stacks）
- mark_dirty 对应 stat

- [ ] **Step 4: remove_by_instance 时同步维护 inst_id_by_ownership**

当移除实例时：
- 若 `inst.ownership_key` 存在且映射到该 inst_id，则清理 `inst_id_by_ownership[ownership_key]`

- [ ] **Step 5: 实现非 DOT 的到期递减与移除（tick_phase 支持 START/END）**

在 `BuffCore.on_turn_start/on_turn_end`（或其内部公共函数）里：
- 遍历 `inst_ids.duplicate()`
- 找到 `duration.type=="TURNS"` 且 turns>0 的实例
- 若 `duration.tick_phase == 当前阶段`：
  - `inst.remaining_turns -= 1`
  - `<=0` 则 `remove_by_instance(stats, inst_id, true)`

> 注意：需要能拿到 owner_stats。当前 BuffCore 中 owner_entity_id 已绑定，可从 `stats_by_entity[owner_entity_id]` 取到。

- [ ] **Step 6: 跑全部 GUT tests，修到全绿**

重点看：
- `tests/rpg/test_buff_lifecycle_stacking.gd`
- `tests/rpg/test_buff_lifecycle_expire.gd`
- 以及现有的伤害/DOT/驱散/整回合测试不回归

- [ ] **Step 7: 提交实现**

```bash
git add godot-buff/addons/omnibuff/runtime/core/buff_core.gd
git commit -m "feat(lifecycle): implement stacking modes and non-dot turn expiry"
```

---

## Self-Review

- [ ] 搜索 plan 产出代码中无 TODO/TBD/临时注释
- [ ] A1：REPLACE/ADD_STACK/MULTI_INSTANCE + ownership_mode 都有对应 GUT 用例
- [ ] A3：普通 TURNS buff 在指定 tick_phase 到期移除，有 GUT 用例

