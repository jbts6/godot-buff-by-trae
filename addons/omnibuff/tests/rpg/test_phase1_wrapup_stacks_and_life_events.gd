extends GutTest

## Phase 1 收尾验收：
## - Stack 精细控制（ADD_STACKS / SET_STACKS）
## - LIFE 事件域（DEATH / REVIVE）：击杀回血、复活清 DEBUFF

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const LifeContext := preload("res://addons/omnibuff/runtime/core/life_context.gd")


func _count_instances_by_buff_id(buffs: RefCounted, ds: OmniCompiledDataset, buff_id_str: String) -> int:
	var cnt: int = 0
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		var def: Dictionary = ds.buff_defs[int(inst.buff_def_id)]
		if String(def.get("id", "")) == buff_id_str:
			cnt += 1
	return cnt


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


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid := int(ds.stat_id(stat_name))
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	var stats: OmniStatsComponent = entity.get("stats", null)
	assert_not_null(stats)
	stats.add_base(sid, v - float(stats.get_final(sid)))
	assert_true(is_equal_approx(float(stats.get_final(sid)), v), "failed to set %s to %s" % [stat_name, v])


func test_add_and_set_stacks_actions() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker := TestBattle.make_entity(9901, ds, enums_rt)
	var defender := TestBattle.make_entity(9902, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])
	var tags_mask := int(enums_rt.tag_mask(["BUFF"]))

	# defender 持有一个 debuff（3层）
	for i in range(3):
		defender["buffs"].apply_buff(defender["stats"], "buff_dummy_debuff_stackable_3", int(defender["id"]))
	assert_eq(_count_stacks_by_buff_id(defender["buffs"], ds, "buff_dummy_debuff_stackable_3"), 3)

	# 触发一个 action：ADD_STACKS -1
	defender["buffs"].apply_buff(defender["stats"], "buff_wrapup_add_stacks_minus1", int(defender["id"]))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 1.0, replay, 1, tags_mask, runtime)
	assert_eq(_count_stacks_by_buff_id(defender["buffs"], ds, "buff_dummy_debuff_stackable_3"), 2)

	# 触发一个 action：SET_STACKS 0（应移除）
	defender["buffs"].apply_buff(defender["stats"], "buff_wrapup_set_stacks_zero", int(defender["id"]))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 1.0, replay, 2, tags_mask, runtime)
	assert_eq(_count_stacks_by_buff_id(defender["buffs"], ds, "buff_dummy_debuff_stackable_3"), 0)


func test_life_death_kill_heal_and_revive_clean_debuff() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var attacker := TestBattle.make_entity(9911, ds, enums_rt)
	var victim := TestBattle.make_entity(9912, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, victim])

	var hp_id := int(ds.stat_id("HP"))
	assert_true(hp_id >= 0)
	_set_stat_final(attacker, ds, "HP", 100.0)

	# victim：挂“死亡时给 killer 回血”
	victim["buffs"].apply_buff(victim["stats"], "buff_wrapup_on_death_heal_killer_50", int(victim["id"]))

	# 模拟死亡事件：source_id = attacker
	var death := LifeContext.new()
	death.actor_id = int(victim["id"])
	death.source_id = int(attacker["id"])
	death.tags_mask = int(enums_rt.tag_mask(["BUFF"]))
	death.set_meta("runtime", runtime)
	victim["buffs"].emit_event("LIFE", "DEATH", death)
	assert_true(is_equal_approx(float(attacker["stats"].get_final(hp_id)), 150.0), "killer should be healed +50 on death")

	# victim：挂一个 DEBUFF 标记 + 一个“复活清 debuff” buff
	victim["buffs"].apply_buff(victim["stats"], "buff_dummy_debuff_mark_1", int(victim["id"]))
	victim["buffs"].apply_buff(victim["stats"], "buff_wrapup_on_revive_clean_debuff", int(victim["id"]))
	assert_eq(_count_instances_by_buff_id(victim["buffs"], ds, "buff_dummy_debuff_mark_1"), 1)

	var revive := LifeContext.new()
	revive.actor_id = int(victim["id"])
	revive.source_id = -1
	revive.tags_mask = int(enums_rt.tag_mask(["BUFF"]))
	revive.set_meta("runtime", runtime)
	victim["buffs"].emit_event("LIFE", "REVIVE", revive)
	assert_eq(_count_instances_by_buff_id(victim["buffs"], ds, "buff_dummy_debuff_mark_1"), 0, "revive should clean DEBUFF")
