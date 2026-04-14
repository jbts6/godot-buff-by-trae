extends GutTest

## 用例：多段攻击（3段）每段命中都应触发 AFTER_DEAL 的 APPLY_BUFF，并在 TurnEnd 产生对应 DOT 追帧
##
## 场景：
## - attacker 身上挂 buff_on_hit_apply_dot（AFTER_DEAL scope=TARGET action APPLY_BUFF buff_dot_fire_3t）
## - 对 defender 连续 3 段攻击（base=12/14/18, tags_mask=BUFF）
## - 断言 defender 的 buff 实例数为 3（全部为 buff_dot_fire_3t）
## - 执行 TurnComponent.on_turn_end 一次，断言新增 3 条 DotTrace，且 source_entity_id 全为 attacker

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_multihit_each_hit_applies_dot_and_ticks_three_traces() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	var attacker_id := 7001
	var defender_id := 7002

	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	# attacker：每次命中后给目标挂 DOT（MULTI_INSTANCE）
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_apply_dot", attacker_id)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 连续 3 段攻击：每段 AFTER_DEAL 都应触发一次 APPLY_BUFF
	var base_hits := [12.0, 14.0, 18.0]
	for i in range(base_hits.size()):
		pipe.deal_damage(
			attacker.stats,
			defender.stats,
			attacker.buffs,
			defender.buffs,
			ds,
			float(base_hits[i]),
			replay,
			100 + i,
			tags_mask,
			runtime
		)

	# 断言：defender 身上应有 3 个 buff 实例，且全部为 buff_dot_fire_3t
	assert_eq(defender.buffs.inst_ids.size(), 3, "defender should have 3 buff instances after 3 hits")
	for inst_id in defender.buffs.inst_ids:
		var inst = defender.buffs.instances_by_id.get(int(inst_id), null)
		assert_not_null(inst, "buff instance should exist: inst_id=%s" % [inst_id])
		var def: Dictionary = ds.buff_defs[int(inst.buff_def_id)]
		assert_eq(String(def.get("id", "")), "buff_dot_fire_3t")

	# TurnEnd：一次 tick 应产生 3 条 DotTrace（每个 DOT 实例一条），来源都归因到 attacker
	var turn := OmniTurnComponent.new()
	var entity_ids := PackedInt32Array([attacker_id, defender_id])
	entity_ids.sort()

	var before := replay.dot_traces.size()
	turn.on_turn_end(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	var after := replay.dot_traces.size()

	assert_eq(after - before, 3, "one tick should create 3 dot traces for 3 dot instances")
	for i in range(before, after):
		assert_eq(int(replay.dot_traces[i].source_entity_id), attacker_id)
		assert_eq(int(replay.dot_traces[i].target_entity_id), defender_id)

