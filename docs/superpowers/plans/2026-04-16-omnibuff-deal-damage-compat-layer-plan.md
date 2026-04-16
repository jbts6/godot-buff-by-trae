# OmniBuff deal_damage Compat Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `OmniDamagePipeline.deal_damage()` 提供稳定的兼容入口 `deal_damage_v1()`（不含 is_bonus_damage），并在 `OmniBuff` singleton 中补充对外推荐说明；新增测试确保 wrapper 可用。

**Architecture:** 在 `damage_pipeline.gd` 新增 wrapper：`deal_damage_v1(...) -> deal_damage(..., is_bonus_damage=false)`；必要时新增 `deal_damage_bonus(...)` 供内部使用；在 singleton 侧仅做注释/暴露提示，避免使用方直接依赖易变签名。

**Tech Stack:** Godot 4.7 + GDScript + GUT tests。

---

## 0) 文件清单

- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/omnibuff_singleton.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_damage_pipeline_deal_damage_v1_compat.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_damage_pipeline_deal_damage_v1_compat.gd.uid`

---

## Task 1：写 failing test（RED）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_damage_pipeline_deal_damage_v1_compat.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_damage_pipeline_deal_damage_v1_compat.gd.uid`

- [ ] **Step 1: 测试代码**

```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")

func test_deal_damage_v1_should_work() -> void:
    var loaded := TestDataset.load_rpg_tests(true)
    var enums_rt: OmniEnumsRuntime = loaded.enums_rt
    var ds: OmniCompiledDataset = loaded.ds
    var pipe := OmniDamagePipeline.new()
    var replay: OmniReplay = ReplayScript.new()
    var a := TestBattle.make_entity(9801, ds, enums_rt)
    var d := TestBattle.make_entity(9802, ds, enums_rt)
    var rt := TestBattle.make_runtime([a, d])
    var ctx = pipe.deal_damage_v1(a.stats, d.stats, a.buffs, d.buffs, ds, 10.0, replay, 1, 0, rt, 0, -1, 0, 0)
    assert_not_null(ctx)
```

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_damage_pipeline_deal_damage_v1_compat.gd addons/omnibuff/tests/rpg/test_damage_pipeline_deal_damage_v1_compat.gd.uid
git -C godot-buff commit -m "test(compat): add failing coverage for deal_damage_v1 wrapper"
```

---

## Task 2：实现 deal_damage_v1 wrapper（GREEN）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`

- [ ] **Step 1: 新增 deal_damage_v1**

```gdscript
func deal_damage_v1(attacker: OmniStatsComponent, defender: OmniStatsComponent, buff_attacker: OmniBuffCore, buff_defender: OmniBuffCore, ds: OmniCompiledDataset, base_damage: float, replay: RefCounted = null, turn_index: int = 0, tags_mask: int = 0, runtime: Dictionary = {}, roll_key: int = 0, skill_id: int = -1, damage_type: int = 0, element: int = 0) -> DamageContext:
    return deal_damage(attacker, defender, buff_attacker, buff_defender, ds, base_damage, replay, turn_index, tags_mask, runtime, roll_key, skill_id, damage_type, element, false)
```

- [ ] **Step 2 (可选): 新增 deal_damage_bonus**
供内部使用：
```gdscript
func deal_damage_bonus(...same args...) -> DamageContext:
    return deal_damage(..., true)
```

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/damage_pipeline.gd
git -C godot-buff commit -m "feat(compat): add deal_damage_v1 wrapper"
```

---

## Task 3：singleton 对外说明

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/omnibuff_singleton.gd`

- [ ] **Step 1: 注释增加“稳定 API 推荐”**
强调：
- 外部如果需要稳定性，请使用 `deal_damage_v1`
- 不建议大量使用位置参数调用未来可能变更的内部签名

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/omnibuff_singleton.gd
git -C godot-buff commit -m "docs(singleton): document deal_damage_v1 as stable API"
```

---

## 最终验证

- [ ] `test_damage_pipeline_deal_damage_v1_compat.gd` 通过
- [ ] bonus/value/ratio/expr 相关测试仍通过

