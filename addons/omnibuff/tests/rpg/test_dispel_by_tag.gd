extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _count_by_id(buffs: OmniBuffCore, ds: OmniCompiledDataset, buff_id_str: String) -> int:
	var n := 0
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		if String(ds.buff_defs[int(inst.buff_def_id)].get("id", "")) == buff_id_str:
			n += 1
	return n


func test_dispel_by_tag_debuff_clears_dot_instances() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()
	var turn = OmniTurnComponent.new()

	var attacker = TestBattle.make_entity(7601, ds, enums_rt)
	var defender = TestBattle.make_entity(7602, ds, enums_rt)
	var runtime = TestBattle.make_runtime([attacker, defender])
	var ids = PackedInt32Array([7601, 7602])
	ids.sort()
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 让 attacker 触发 AFTER_DEAL 挂 DOT
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_apply_dot", 7601)
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 12.0, replay, 1, tags_mask, runtime)
	assert_eq(_count_by_id(defender.buffs, ds, "buff_dot_fire_3t"), 1)

	# TurnStart tick 一次，确认会产生 trace
	var before = replay.dot_traces.size()
	turn.on_turn_start(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, replay)
	assert_eq(replay.dot_traces.size() - before, 1)

	# 驱散 DEBUFF：应移除 DOT，且后续 tick 不再产生 trace
	var removed: int = int(defender.buffs.dispel_by_tag(defender.stats, "DEBUFF", false))
	assert_eq(removed, 1)
	assert_eq(_count_by_id(defender.buffs, ds, "buff_dot_fire_3t"), 0)

	before = replay.dot_traces.size()
	turn.on_turn_start(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, replay)
	assert_eq(replay.dot_traces.size() - before, 0)


func test_dispel_by_tag_include_implicit_false_keeps_implicit_and_passive() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7603, ds, enums_rt)

	e.buffs.apply_buff(e.stats, "buff_dispel_implicit_atk_10", 1)
	e.buffs.apply_buff(e.stats, "buff_dispel_passive_atk_10", 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_implicit_atk_10"), 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_passive_atk_10"), 1)

	var removed: int = int(e.buffs.dispel_by_tag(e.stats, "BUFF", false))
	assert_eq(removed, 0)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_implicit_atk_10"), 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_passive_atk_10"), 1)


func test_dispel_by_tag_include_implicit_true_removes_implicit_and_passive() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7604, ds, enums_rt)

	e.buffs.apply_buff(e.stats, "buff_dispel_implicit_atk_10", 1)
	e.buffs.apply_buff(e.stats, "buff_dispel_passive_atk_10", 1)

	var removed: int = int(e.buffs.dispel_by_tag(e.stats, "BUFF", true))
	assert_eq(removed, 2)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_implicit_atk_10"), 0)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_passive_atk_10"), 0)

