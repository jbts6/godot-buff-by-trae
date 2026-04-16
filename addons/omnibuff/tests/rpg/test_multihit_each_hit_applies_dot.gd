extends GutTest

## 用例：多段攻击（3段）每段命中都应触发 AFTER_DEAL 的 APPLY_BUFF；
##      DOT 挂上的当回合不结算，下一回合开始（TurnStart）结算并产出追帧
##
## 场景：
## - attacker 身上挂 buff_on_hit_apply_dot（AFTER_DEAL scope=TARGET action APPLY_BUFF buff_dot_fire_3t）
## - 对 defender 连续 3 段攻击（base=12/14/18, tags_mask=BUFF）
## - 断言 defender 身上仅 1 个 DOT buff 实例（同来源合并），stacks=3
## - 执行 TurnComponent.on_turn_end 推进到下一回合（不结算 DOT）
## - 执行 TurnComponent.on_turn_start 结算 DOT：
##   - DOT 按来源合并：同一来源仅 1 条 DotTrace
##   - source_entity_id 为 attacker

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _find_dot_inst_by_source(buffs: OmniBuffCore, ds: OmniCompiledDataset, buff_id_str: String, source_entity_id: int) -> Variant:
	var bdid := int(ds.buff_id(buff_id_str))
	assert_true(bdid >= 0, "unknown buff_id=%s" % [buff_id_str])
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		if int(inst.buff_def_id) == bdid and int(inst.source_entity_id) == source_entity_id:
			return inst
	return null


func test_multihit_each_hit_applies_dot_and_ticks_traces() -> void:
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

	# 断言：同一来源 + 同一 dot buff_id 应合并为 1 个实例，stacks 随命中递增（3 次 => stacks=3）
	var inst = _find_dot_inst_by_source(defender.buffs, ds, "buff_dot_fire_3t", attacker_id)
	assert_not_null(inst)
	assert_eq(defender.buffs.inst_ids.size(), 1, "defender should have only 1 DOT buff instance (merge-by-source)")
	assert_eq(int(inst.stacks), 3, "DOT stacks should be 3 after 3 hits (+1 per hit)")

	# DOT 默认在 TURN_START 结算：
	# - TurnEnd：仅推进到下一回合，不应产出 dot trace
	# - TurnStart：DOT 按来源合并后，一次 tick 应产生 1 条 DotTrace（同一来源）
	var turn := OmniTurnComponent.new()
	var entity_ids := PackedInt32Array([attacker_id, defender_id])
	entity_ids.sort()

	var before_end := replay.dot_traces.size()
	turn.on_turn_end(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	var after_end := replay.dot_traces.size()
	assert_eq(after_end - before_end, 0, "applying dots this turn should not tick at turn end (TURN_START semantics)")

	var before := replay.dot_traces.size()
	turn.on_turn_start(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	var after := replay.dot_traces.size()

	assert_eq(after - before, 1, "one tick should create 1 dot trace per source (merge-by-source)")
	for i in range(before, after):
		assert_eq(int(replay.dot_traces[i].source_entity_id), attacker_id)
		assert_eq(int(replay.dot_traces[i].target_entity_id), defender_id)


func test_apply_buff_action_add_stacks_can_add_two_per_hit() -> void:
	## 用例：触发器 action.add_stacks=2 时，每次命中应增加 2 层（而不是固定 +1）
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	var attacker_id := 7011
	var defender_id := 7012

	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	# attacker：每次命中后给目标挂 DOT（每次 +2 stacks）
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_apply_dot_add2", attacker_id)
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var base_hits := [12.0, 14.0, 18.0]
	for i in range(base_hits.size()):
		pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, float(base_hits[i]), replay, 200 + i, tags_mask, runtime)

	var inst2 = _find_dot_inst_by_source(defender.buffs, ds, "buff_dot_fire_3t", attacker_id)
	assert_not_null(inst2)
	assert_eq(defender.buffs.inst_ids.size(), 1)
	assert_eq(int(inst2.stacks), 6, "3 hits * add_stacks(2) => stacks=6")
