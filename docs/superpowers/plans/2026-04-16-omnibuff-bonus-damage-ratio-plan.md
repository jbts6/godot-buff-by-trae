# OmniBuff BONUS_DAMAGE Ratio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 扩展 `BONUS_DAMAGE` 支持 `ratio`（按 ctx.final_damage * ratio 计算追加伤害），并保持不递归（require_not_bonus_damage + is_bonus_damage guard），提供 tests+demo 验收。

**Architecture:** 在 `buff_core.gd::_bonus_damage_from_event` 内，如果 action 配置了 ratio，则从当前 ctx.final_damage 计算 bonus base_damage；随后调用一次 `deal_damage(..., is_bonus_damage=true)` 产生 bonus 伤害。validators 放行并校验 ratio/min/max/round_mode 等字段。

**Tech Stack:** Godot 4.7 + GDScript + OmniBuffCore + OmniDamagePipeline + validators + GUT + buff_ui_demo。

---

## 0) 文件清单

- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`（BONUS_DAMAGE action payload 扩展）
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`（ratio 计算 + roll_key offset）
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`（action schema）
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`（新增 ratio 测试 buff）
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_ratio_nonrecursive.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_ratio_nonrecursive.gd.uid`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

---

## Task 1：写 failing tests（RED）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_ratio_nonrecursive.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_ratio_nonrecursive.gd.uid`

- [ ] **Step 1: 写测试**

```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const Executor := preload("res://addons/omnibuff/runtime/core/battle_executor.gd")
const CommandContext := preload("res://addons/omnibuff/runtime/core/command_context.gd")
const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")

func test_bonus_damage_ratio_should_use_final_damage() -> void:
    var loaded := TestDataset.load_rpg_tests(true)
    var enums_rt: OmniEnumsRuntime = loaded.enums_rt
    var ds: OmniCompiledDataset = loaded.ds
    var sources: Dictionary = loaded.result.sources
    var pipe := OmniDamagePipeline.new()
    var exec := Executor.new()
    var replay: OmniReplay = ReplayScript.new()
    var attacker_id := 9601
    var defender_id := 9602
    var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
    var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
    var runtime := TestBattle.make_runtime([attacker, defender])
    attacker.buffs.apply_buff(attacker.stats, "buff_bonus_damage_ratio_50p_nonrecursive", attacker_id)
    var cmd := CommandContext.new()
    cmd.actor_id = attacker_id
    cmd.command_kind = "ATTACK"
    cmd.targets = PackedInt32Array([defender_id])
    cmd.skill_id = 1
    var before := int(replay.damage_traces.size())
    exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, replay)
    var after := int(replay.damage_traces.size())
    assert_eq(after - before, 2)
    var t0 = replay.damage_traces[before + 0]
    var t1 = replay.damage_traces[before + 1]
    var expected := float(t0.final_damage) * 0.5
    assert_true(abs(float(t1.base_damage) - expected) < 0.0001)
```

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_bonus_damage_ratio_nonrecursive.gd addons/omnibuff/tests/rpg/test_bonus_damage_ratio_nonrecursive.gd.uid
git -C godot-buff commit -m "test(bonus): add failing coverage for bonus damage ratio"
```

---

## Task 2：扩展 EventIndex Listener payload

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`

- [ ] **Step 1: 新增字段**
在 Listener 增加：
- `action_bonus_ratio: float = 0.0`
- `action_bonus_min_damage: float = 0.0`
- `action_bonus_max_damage: float = 0.0`
- `action_bonus_round_mode: String = ""`

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/event_index.gd
git -C godot-buff commit -m "feat(bonus): extend action payload for ratio"
```

---

## Task 3：BuffCore 解析 + 计算 ratio

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 注册解析**
在 `_register_triggers_for_instance` 的 BONUS_DAMAGE 分支解析：
- ratio/min_damage/max_damage/round_mode

- [ ] **Step 2: ratio 计算**
在 `_bonus_damage_from_event`：
- 若 `l.action_bonus_ratio > 0`：`bd = ctx.final_damage * l.action_bonus_ratio`
- 依次应用 min/max/round_mode（NONE/FLOOR/ROUND/CEIL）
- roll_key 偏移改为 `ctx.roll_key + 20000`（区分固定 value）

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m "feat(bonus): support ratio-based bonus damage"
```

---

## Task 4：validators + rpg_tests buff_defs

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: validators**
- 放行 action 字段：ratio/min_damage/max_damage/round_mode
- 校验：ratio 在 (0,10]；value 与 ratio 至少一个（建议两者同时出现时报错）

- [ ] **Step 2: buff_defs 新增 buff_bonus_damage_ratio_50p_nonrecursive**
- event: DAMAGE/AFTER_DEAL
- filters: require_not_bonus_damage=true
- action: BONUS_DAMAGE(ratio=0.5, tags_mask_any=["BONUS_DAMAGE"])

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/config/compiler/validators.gd data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "feat(validate): support bonus damage ratio and add test buff"
```

---

## Task 5：Demo scenario

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: 新增 scenario bonus_damage_ratio_nonrecursive**
输出：
- base.final_damage
- expected bonus
- actual bonus trace.base_damage

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m "feat(demo): add bonus damage ratio scenario"
```

---

## 最终验证

- [ ] `test_bonus_damage_ratio_nonrecursive.gd` 全绿
- [ ] `test_bonus_damage_nonrecursive.gd` 仍绿
- [ ] demo 两个 bonus 场景都可复现

