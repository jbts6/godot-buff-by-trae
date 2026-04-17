# OmniBuff Phase 1 Wrap-up (Stacks + LIFE Events) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 Phase 1 收尾两块缺口：① Stack 精细控制（ADD_STACKS/SET_STACKS action + BuffCore 最小 API）；② 新增 LIFE 事件域（DEATH/REVIVE）并覆盖“击杀回血/复活清 DEBUFF”的 tests + demo。

**Architecture:** 扩展 enums（event_type=LIFE、event_phase=DEATH/REVIVE、action_kind=ADD_STACKS/SET_STACKS）；新增 `LifeContext`；在 BuffCore 增加 stacks 操作 API + 新 action 执行；battle_executor/demo 侧提供触发入口与可观测场景；validators 全面治理并给出错误提示。

**Tech Stack:** Godot 4.7 + GDScript + GUT + buff_ui_demo。

---

## 0) 文件清单

**Core / Runtime**
- Create: `godot-buff/addons/omnibuff/runtime/core/life_context.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/life_context.gd.uid`
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`（新增 filter 字段/ action payload）
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`（BuffCore stacks API + action 执行 + LIFE filters）
- Modify: `godot-buff/addons/omnibuff/runtime/core/battle_executor.gd`（提供 `notify_life_event(...)` 或 demo 使用的最小触发入口）

**Data / Validators**
- Modify: `godot-buff/data/base_demo/enums.json`
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`（新增测试 buff：stack actions + life events）

**Tests / Demo**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_phase1_wrapup_stacks_and_life_events.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_phase1_wrapup_stacks_and_life_events.gd.uid`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

---

## Task 1：写 failing tests（RED）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_phase1_wrapup_stacks_and_life_events.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_phase1_wrapup_stacks_and_life_events.gd.uid`

- [ ] **Step 1: 写测试**

```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const LifeContext := preload("res://addons/omnibuff/runtime/core/life_context.gd")

func _count_stacks_by_buff_id(buffs: RefCounted, ds: OmniCompiledDataset, buff_id_str: String) -> int:
	var total := 0
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		var def: Dictionary = ds.buff_defs[int(inst.buff_def_id)]
		if String(def.get("id", "")) == buff_id_str:
			total += int(inst.stacks)
	return total

func test_add_and_set_stacks_actions() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()
	var attacker := TestBattle.make_entity(9901, ds, enums_rt)
	var defender := TestBattle.make_entity(9902, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	# defender 持有一个 debuff（3层）
	defender.buffs.apply_buff(defender.stats, "buff_dummy_debuff_stackable_3", int(defender.id))
	assert_eq(_count_stacks_by_buff_id(defender.buffs, ds, "buff_dummy_debuff_stackable_3"), 3)

	# 触发一个 action：ADD_STACKS -1
	defender.buffs.apply_buff(defender.stats, "buff_wrapup_add_stacks_minus1", int(defender.id))
	var tags_mask := int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 1.0, replay, 1, tags_mask, runtime)
	assert_eq(_count_stacks_by_buff_id(defender.buffs, ds, "buff_dummy_debuff_stackable_3"), 2)

	# 触发一个 action：SET_STACKS 0（应移除）
	defender.buffs.apply_buff(defender.stats, "buff_wrapup_set_stacks_zero", int(defender.id))
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 1.0, replay, 2, tags_mask, runtime)
	assert_eq(_count_stacks_by_buff_id(defender.buffs, ds, "buff_dummy_debuff_stackable_3"), 0)

func test_life_death_kill_heal_and_revive_clean_debuff() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var attacker := TestBattle.make_entity(9911, ds, enums_rt)
	var victim := TestBattle.make_entity(9912, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, victim])

	# victim：挂“死亡时给 killer 回血”
	victim.buffs.apply_buff(victim.stats, "buff_wrapup_on_death_heal_killer_50", int(victim.id))

	# 模拟死亡事件：source_id = attacker
	var death := LifeContext.new()
	death.actor_id = int(victim.id)
	death.source_id = int(attacker.id)
	death.tags_mask = int(enums_rt.tag_mask(["BUFF"]))
	death.set_meta("runtime", runtime)
	victim.buffs.emit_event("LIFE", "DEATH", death)

	var hp_id := int(ds.stat_id("HP"))
	assert_true(float(attacker.stats.get_final(hp_id)) > 0.0, "killer should be healed (hp increased)")

	# revive 清 DEBUFF（victim 自己）
	victim.buffs.apply_buff(victim.stats, "buff_dummy_debuff_mark_1", int(victim.id))
	assert_true(victim.buffs.inst_ids.size() >= 2)
	var revive := LifeContext.new()
	revive.actor_id = int(victim.id)
	revive.source_id = -1
	revive.tags_mask = int(enums_rt.tag_mask(["BUFF"]))
	revive.set_meta("runtime", runtime)
	victim.buffs.emit_event("LIFE", "REVIVE", revive)
	# 期望：DEBUFF 被清（保留“死亡回血 buff”本体）
	# 具体断言以实现的 debuff 标记/驱散策略为准（见 buff_defs）
```

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_phase1_wrapup_stacks_and_life_events.gd addons/omnibuff/tests/rpg/test_phase1_wrapup_stacks_and_life_events.gd.uid
git -C godot-buff commit -m "test(phase1): add failing coverage for stacks and life events"
```

---

## Task 2：enums 扩展（event_type/phase/action_kind）

**Files:**
- Modify: `godot-buff/data/base_demo/enums.json`

- [ ] **Step 1: 增加枚举项**
- `event_type`: 添加 `LIFE`
- `event_phase`: 添加 `DEATH`, `REVIVE`
- `action_kind`: 添加 `ADD_STACKS`, `SET_STACKS`

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add data/base_demo/enums.json
git -C godot-buff commit -m "feat(enums): add LIFE events and stack actions"
```

---

## Task 3：新增 LifeContext

**Files:**
- Create: `godot-buff/addons/omnibuff/runtime/core/life_context.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/life_context.gd.uid`

- [ ] **Step 1: 实现**

```gdscript
class_name OmniLifeContext
extends RefCounted

var actor_id: int = -1
var source_id: int = -1
var tags_mask: int = 0
```

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/life_context.gd addons/omnibuff/runtime/core/life_context.gd.uid
git -C godot-buff commit -m "feat(life): add life context"
```

---

## Task 4：EventIndex / Listener 扩展（payload + filters）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`

- [ ] **Step 1: Listener 新增字段**
- filters: `filter_actor_id: int = -1`, `filter_source_id: int = -1`
- action: `action_stack_buff_id: String = ""`, `action_stack_delta: int = 0`, `action_stack_value: int = 0`, `action_stack_min: int = 0`, `action_stack_max: int = 0`

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/event_index.gd
git -C godot-buff commit -m "feat(phase1): extend listener for life filters and stack actions"
```

---

## Task 5：BuffCore：stacks API + action 执行 + LIFE filter

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: BuffCore 新增 stacks API**
- `add_stacks_by_buff_id(...)`
- `set_stacks_by_buff_id(...)`

- [ ] **Step 2: 注册解析**
在 `_register_triggers_for_instance`：
- 解析 LIFE 的 filters：actor_id/source_id（可选）
- 解析 action：ADD_STACKS/SET_STACKS payload

- [ ] **Step 3: emit_event 执行分支**
新增：
- `_add_stacks_from_event(l, ctx)`
- `_set_stacks_from_event(l, ctx)`

并对 LIFE 事件做过滤：
- `filter_actor_id`：对比 ctx.actor_id
- `filter_source_id`：对比 ctx.source_id

- [ ] **Step 4: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m "feat(phase1): stacks control and LIFE event filters"
```

---

## Task 6：validators + rpg_tests buff_defs

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: validators**
- 放行 `event_type=LIFE`, `event_phase=DEATH/REVIVE`
- 放行 LIFE filters：actor_id/source_id（仅 LIFE）
- 放行 action：ADD_STACKS/SET_STACKS 并校验字段

- [ ] **Step 2: buff_defs 新增测试 buff**
需要新增（示例 id，可按现有命名风格调整）：
- `buff_dummy_debuff_stackable_3`（一个可叠层 debuff，初始 3 层）
- `buff_wrapup_add_stacks_minus1`（AFTER_TAKE 或 AFTER_DEAL：对 target 的某 buff ADD_STACKS -1）
- `buff_wrapup_set_stacks_zero`（同上：SET_STACKS 0）
- `buff_wrapup_on_death_heal_killer_50`（LIFE/DEATH：scope=SOURCE → HEAL 50）
- `buff_wrapup_on_revive_clean_debuff`（LIFE/REVIVE：scope=SELF → DISPEL BY_TAG DEBUFF）

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/config/compiler/validators.gd data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "feat(validate): support LIFE events and stack actions"
```

---

## Task 7：Demo scenarios

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: 新增 scenarios**
- `phase1_wrapup_stacks_add_remove`
- `phase1_wrapup_life_death_kill_heal`
- `phase1_wrapup_life_revive_clean_debuff`

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m "feat(demo): add phase1 wrapup scenarios (stacks/life)"
```

---

## 最终验证

- [ ] `test_phase1_wrapup_stacks_and_life_events.gd` 全绿
- [ ] 既有 Phase 1 tests 全绿（filters/actions/command）
- [ ] demo 场景可复现并能从 HUD 看清触发链

