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


func test_remove_by_buff_id_reverts_stats() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7501, ds, enums_rt)

	var atk_id := ds.stat_id("ATK")
	e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3", 111) # ATK +10
	assert_eq(float(e.stats.get_final(atk_id)), 20.0)

	var removed: int = int(e.buffs.remove_by_buff_id(e.stats, "buff_life_stack_atk_10_2t_max3", "ALL"))
	assert_eq(removed, 1)
	assert_eq(float(e.stats.get_final(atk_id)), 10.0)


func test_remove_by_tag_removes_all_debuff() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7502, ds, enums_rt)

	# rpg_tests 里已有 debuff：buff_dot_fire_3t（tags: DEBUFF/DOT/FIRE）
	e.buffs.apply_buff(e.stats, "buff_dot_fire_3t", 111)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dot_fire_3t"), 1)

	var removed: int = int(e.buffs.remove_by_tag(e.stats, "DEBUFF", "ALL"))
	assert_eq(removed, 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dot_fire_3t"), 0)


func test_remove_by_buff_id_stops_event_trigger() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()

	var attacker = TestBattle.make_entity(7503, ds, enums_rt)
	var defender = TestBattle.make_entity(7504, ds, enums_rt)
	var runtime = TestBattle.make_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# attacker 挂 AFTER_DEAL -> APPLY_BUFF(DOT)
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_apply_dot", 7503)

	# 打一段：应挂 DOT
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 12.0, replay, 1, tags_mask, runtime)
	assert_eq(_count_by_id(defender.buffs, ds, "buff_dot_fire_3t"), 1)

	# 移除 attacker 的触发 buff，再打：不应再挂 DOT
	var removed: int = int(attacker.buffs.remove_by_buff_id(attacker.stats, "buff_on_hit_apply_dot", "ALL"))
	assert_eq(removed, 1)
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 12.0, replay, 2, tags_mask, runtime)
	assert_eq(_count_by_id(defender.buffs, ds, "buff_dot_fire_3t"), 1)


func test_remove_inactive_instance_works() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7505, ds, enums_rt)

	var hp_id := ds.stat_id("HP")
	var atk_id := ds.stat_id("ATK")
	# 初始 HP=100，不满足 HP<=50，实例会 inactive
	e.buffs.apply_buff(e.stats, "buff_cond_hp_le_50_atk_up_10", 111)
	assert_eq(float(e.stats.get_final(atk_id)), 10.0)
	assert_eq(_count_by_id(e.buffs, ds, "buff_cond_hp_le_50_atk_up_10"), 1)

	var removed: int = int(e.buffs.remove_by_buff_id(e.stats, "buff_cond_hp_le_50_atk_up_10", "ALL"))
	assert_eq(removed, 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_cond_hp_le_50_atk_up_10"), 0)

	# 扣血到 50 也不应再“复活”该 buff
	e.stats.add_base(hp_id, -50.0)
	assert_eq(float(e.stats.get_final(atk_id)), 10.0)

