# AOE Multi-Target Multi-Hit + DOT Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增加一个“复杂回归用例”证明：AOE 多目标 + 每目标独立命中/暴击 + 多段 AOE 每段挂 DOT 能跑通（并保持确定性、可断言）。

**Architecture:** 最小改动：只新增一个测试专用 buff（require_hit=true）+ 新增一个 GUT 集成测试；不改运行时逻辑。

**Tech Stack:** Godot 4.7 + GDScript + GUT + JSON（测试数据）。

---

## 0) 文件清单

**数据：**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_aoe_multitarget_multihit_per_target_hit_crit_and_dot.gd`

---

## Task 1：新增测试专用 buff（require_hit 的 APPLY_BUFF）

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 追加一个 buff 定义**

在 buffs 数组中追加：
```json
{
  "id": "buff_on_hit_apply_dot_require_hit",
  "name": "测试：命中后给目标挂灼烧（require_hit）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [],
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "AFTER_DEAL",
      "scope": "TARGET",
      "filters": { "tag_mask_any": ["BUFF"], "require_hit": true },
      "action": { "kind": "APPLY_BUFF", "buff_id": "buff_dot_fire_3t" }
    }
  ]
}
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "test(data): add require_hit apply-dot buff for aoe regression"
```

---

## Task 2：新增复杂回归测试（AOE 多目标 + 多段 + per-target hit/crit + DOT）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_aoe_multitarget_multihit_per_target_hit_crit_and_dot.gd`

- [ ] **Step 1: 写 failing test**

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

func _count_buff_instances(entity: Dictionary, ds: OmniCompiledDataset, buff_id_str: String) -> int:
	var cnt: int = 0
	for inst_id in entity.buffs.inst_ids:
		var inst = entity.buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		var def: Dictionary = ds.buff_defs[int(inst.buff_def_id)]
		if String(def.get("id", "")) == buff_id_str:
			cnt += 1
	return cnt

func test_aoe_multitarget_multihit_per_target_hit_crit_and_each_hit_applies_dot() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()

	var attacker_id: int = 9601
	var def_a_id: int = 9602
	var def_b_id: int = 9603

	var attacker = TestBattle.make_entity(attacker_id, ds, enums_rt)
	var def_a = TestBattle.make_entity(def_a_id, ds, enums_rt)
	var def_b = TestBattle.make_entity(def_b_id, ds, enums_rt)
	var runtime = TestBattle.make_runtime([attacker, def_a, def_b])

	# AOE：按目标独立命中/暴击
	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(def_a, ds, "EVADE", 0.0) # 必中
	_set_stat_final(def_b, ds, "EVADE", 1.0) # 必闪避（hit_chance=0）

	_set_stat_final(attacker, ds, "CRIT_RATE", 0.5)
	_set_stat_final(attacker, ds, "CRIT_DMG", 1.0)

	# 命中后给目标挂 DOT（require_hit）
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_apply_dot_require_hit", attacker_id)
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var base_hits := [12.0, 14.0, 18.0]
	var targets := [def_a, def_b]

	for seg in range(base_hits.size()):
		var turn_index: int = 300 + seg
		for ti in range(targets.size()):
			var tgt = targets[ti]
			var ctx = pipe.deal_damage(attacker.stats, tgt.stats, attacker.buffs, tgt.buffs, ds, float(base_hits[seg]), replay, turn_index, tags_mask, runtime)

			# 断言：按目标独立命中（def_a 必中、def_b 必 miss）
			if int(tgt.stats.entity_id) == def_a_id:
				assert_true(bool(ctx.hit))
				# crit 期望：按目标 roll（defender_id 参与 seed）
				var crit_roll: float = float(OmniDamagePipeline._roll01(turn_index, attacker_id, def_a_id, OmniDamagePipeline._CRIT_SALT))
				var expect_crit: bool = crit_roll < 0.5
				assert_eq(bool(ctx.crit), expect_crit)
			else:
				assert_false(bool(ctx.hit))
				assert_false(bool(ctx.crit))
				assert_eq(float(ctx.final_damage), 0.0)

	# 伤害追帧：每段 x 每目标 一条
	assert_eq(replay.damage_traces.size(), base_hits.size() * targets.size())

	# DOT：def_a 3段命中 => 3个 DOT buff 实例；def_b 全 miss => 0
	assert_eq(_count_buff_instances(def_a, ds, "buff_dot_fire_3t"), 3)
	assert_eq(_count_buff_instances(def_b, ds, "buff_dot_fire_3t"), 0)

	# 推进到下一回合，TURN_START tick DOT（按来源合并：def_a 只产生 1 条 trace；def_b 无）
	var turn = OmniTurnComponent.new()
	var ids := PackedInt32Array([attacker_id, def_a_id, def_b_id]); ids.sort()
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

	var before: int = int(replay.dot_traces.size())
	turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	var after: int = int(replay.dot_traces.size())

	assert_eq(after - before, 1)
	assert_eq(int(replay.dot_traces[before].source_entity_id), attacker_id)
	assert_eq(int(replay.dot_traces[before].target_entity_id), def_a_id)
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_aoe_multitarget_multihit_per_target_hit_crit_and_dot.gd
git -C godot-buff commit -m "test(rpg): add aoe multitarget multihit dot regression"
```

