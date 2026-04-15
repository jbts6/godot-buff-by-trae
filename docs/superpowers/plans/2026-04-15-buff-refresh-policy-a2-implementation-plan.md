# Buff Refresh Policy (A2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地 A2：让 `ADD_STACK` 命中已有实例时的“刷新剩余回合”行为由 `stack.refresh_policy` 驱动（实现 RESET_TO_MAX；缺失默认 RESET_TO_MAX；其它值暂按不刷新处理），并新增 GUT 用例锁死语义。

**Architecture:** TDD：先在 `data/rpg_tests` 增加一个 `refresh_policy="NONE"` 的对照 buff，再新增 GUT 测试（对比 NONE vs RESET_TO_MAX，且验证缺失默认行为），然后修改 `BuffCore.apply_buff` 中 ADD_STACK 分支，把“无条件重置 remaining_turns”改为“仅在 refresh_policy=RESET_TO_MAX（或缺失）时重置”。最后跑全套 tests。

**Tech Stack:** Godot 4.7 + GDScript + GUT。

---

## 0) 文件清单

**数据：**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_refresh_policy.gd`

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

---

## Task 1：补充 rpg_tests 测试数据（refresh_policy 对照）

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 新增一个不刷新（NONE）的叠层 buff**

```json
{
  "id": "buff_life_stack_atk_10_2t_max3_none",
  "name": "生命周期：ADD_STACK ATK+10（2回合，最多3层，不刷新）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "TURNS", "turns": 2, "tick_phase": "TURN_END" },
  "stack": { "mode": "ADD_STACK", "max_stack": 3, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 10.0 }
  ],
  "triggers": []
}
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/data/rpg_tests/buff_defs.json
git commit -m "test(data): add refresh_policy NONE lifecycle buff"
```

---

## Task 2：新增 GUT 用例：refresh_policy 行为矩阵（最小）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_refresh_policy.gd`

- [ ] **Step 1: 编写 failing test（当前实现会错误刷新 NONE）**

```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_refresh_policy_none_does_not_reset_remaining_turns() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var pipe := OmniDamagePipeline.new()
	var turn := OmniTurnComponent.new()

	var eid := 7301
	var e := TestBattle.make_entity(eid, ds, enums_rt)
	var runtime := TestBattle.make_runtime([e])
	var ids := PackedInt32Array([eid]); ids.sort()

	# 第一次施加：turns=2
	e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3_none", 111)
	var inst_id := int(e.buffs.inst_ids[0])
	assert_eq(int(e.buffs.instances_by_id[inst_id].remaining_turns), 2)

	# Turn1 end：2->1
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null)
	assert_eq(int(e.buffs.instances_by_id[inst_id].remaining_turns), 1)

	# 再次施加（ADD_STACK 命中已有实例）：
	# refresh_policy=NONE => remaining_turns 仍应为 1（不重置到2）
	e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3_none", 111)
	assert_eq(int(e.buffs.instances_by_id[inst_id].remaining_turns), 1)
```

- [ ] **Step 2: 编写通过用例：RESET_TO_MAX 会重置**

```gdscript
func test_refresh_policy_reset_to_max_resets_remaining_turns() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var pipe := OmniDamagePipeline.new()
	var turn := OmniTurnComponent.new()

	var eid := 7302
	var e := TestBattle.make_entity(eid, ds, enums_rt)
	var runtime := TestBattle.make_runtime([e])
	var ids := PackedInt32Array([eid]); ids.sort()

	e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3", 111) # 该 buff refresh_policy=RESET_TO_MAX
	var inst_id := int(e.buffs.inst_ids[0])
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null) # 2->1
	assert_eq(int(e.buffs.instances_by_id[inst_id].remaining_turns), 1)

	e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3", 111) # 命中已有实例，应重置回2
	assert_eq(int(e.buffs.instances_by_id[inst_id].remaining_turns), 2)
```

- [ ] **Step 3: 提交 failing tests**

```bash
git add godot-buff/addons/omnibuff/tests/rpg/test_buff_lifecycle_refresh_policy.gd
git commit -m "test(lifecycle): add refresh_policy tests (NONE vs RESET_TO_MAX)"
```

---

## Task 3：运行时实现：ADD_STACK 的刷新由 refresh_policy 驱动

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 在 apply_buff 的 ADD_STACK 分支读取 refresh_policy**

```gdscript
var refresh_policy := String(stack.get("refresh_policy", ""))
if refresh_policy == "":
	refresh_policy = "RESET_TO_MAX"
```

- [ ] **Step 2: 将“无条件重置 remaining_turns”改为条件重置**

```gdscript
if refresh_policy == "RESET_TO_MAX":
	old_inst.remaining_turns = int(def.get("duration", {}).get("turns", -1))
```

其它值（例如 NONE）保持 remaining_turns 不变。

- [ ] **Step 3: 跑全量 GUT tests，修到全绿**

重点：
- `test_buff_lifecycle_refresh_policy.gd`
- 原有 A1/A3 测试与 RPG 机制用例不回归

- [ ] **Step 4: 提交实现**

```bash
git add godot-buff/addons/omnibuff/runtime/core/buff_core.gd
git commit -m "feat(lifecycle): implement refresh_policy RESET_TO_MAX for ADD_STACK"
```

