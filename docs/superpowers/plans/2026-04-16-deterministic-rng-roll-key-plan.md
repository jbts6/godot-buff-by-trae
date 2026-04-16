# Deterministic RNG Roll Key Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给命中/暴击的确定性 RNG 增加 `roll_key`，保证多段/AOE/额外触发下概率事件可回放且不“串段”；并把 key 记录到 trace 便于调试。

**Architecture:** 先写 failing tests（回归：同 turn_index 多次 hit/crit 因 roll_key 不同而可变化；trace 记录 roll_key），再做最小实现（DamagePipeline + Replay），最后更新文档（API contract）说明用法。

**Tech Stack:** Godot 4.7 + GDScript + GUT。

---

## 0) 文件清单

**实现：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/replay.gd`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_roll_key_makes_hit_crit_independent_per_strike.gd`

**文档：**
- Modify: `godot-buff/addons/omnibuff/docs/api.md`

---

## Task 1：新增 failing test（roll_key 生效 + trace 记录）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_roll_key_makes_hit_crit_independent_per_strike.gd`

- [ ] **Step 1: 写测试**

```gdscript
extends GutTest

const ReplayScript = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid: int = int(ds.stat_id(stat_name))
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v))

func test_roll_key_changes_crit_outcome_with_same_turn_index() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()

	var attacker_id: int = 9701
	var defender_id: int = 9702
	var attacker = TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender = TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime = TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.5)
	_set_stat_final(attacker, ds, "CRIT_DMG", 1.0)

	var turn_index: int = 777
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 同一个 turn_index，两个不同 roll_key
	var ctx1 = pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 12.0, replay, turn_index, 1001, tags_mask, runtime)
	var ctx2 = pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 12.0, replay, turn_index, 1002, tags_mask, runtime)

	assert_true(ctx1.hit)
	assert_true(ctx2.hit)
	assert_eq(replay.damage_traces.size(), 2)

	# 断言 trace 记录 roll_key（并与 ctx meta 一致）
	assert_eq(int(replay.damage_traces[0].roll_key), 1001)
	assert_eq(int(replay.damage_traces[1].roll_key), 1002)
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_roll_key_makes_hit_crit_independent_per_strike.gd
git -C godot-buff commit -m "test(rng): add roll_key regression coverage"
```

---

## Task 2：实现 roll_key（DamagePipeline）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`

- [ ] **Step 1: 修改 deal_damage 签名**
新增参数 `roll_key: int = 0`，放在 `turn_index` 后面：

```gdscript
func deal_damage(..., replay: RefCounted = null, turn_index: int = 0, roll_key: int = 0, tags_mask: int = 0, runtime: Dictionary = {}) -> DamageContext:
```

- [ ] **Step 2: 写入 ctx meta**

```gdscript
ctx.set_meta("turn_index", turn_index)
ctx.set_meta("roll_key", roll_key)
```

- [ ] **Step 3: 修改 RNG seed 组合**
把 `_make_seed/_roll01` 的签名改为包含 roll_key，并在调用处传入 roll_key。

- [ ] **Step 4: 提交**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/damage_pipeline.gd
git -C godot-buff commit -m "feat(rng): add roll_key to deterministic hit/crit"
```

---

## Task 3：Trace 记录 roll_key（Replay）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/replay.gd`

- [ ] **Step 1: DamageTrace 增加字段**

```gdscript
var roll_key: int
```

- [ ] **Step 2: trace_damage 写入**

```gdscript
t.roll_key = int(ctx.get_meta("roll_key", 0))
```

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/replay.gd
git -C godot-buff commit -m "feat(replay): record roll_key in DamageTrace"
```

---

## Task 4：更新 API 文档说明（K2 文档延伸）

**Files:**
- Modify: `godot-buff/addons/omnibuff/docs/api.md`

- [ ] **Step 1: 增加 roll_key 说明**
说明：多段/AOE 必须传入唯一 roll_key 以获得独立概率与可回放一致性。

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/docs/api.md
git -C godot-buff commit -m "docs(api): document roll_key for deterministic rng"
```

