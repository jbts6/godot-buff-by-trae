extends GutTest

const TurnManager = preload("res://addons/turn_manager/runtime/turn_manager.gd")
const BattleContext = preload("res://addons/turn_manager/runtime/battle_context.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")


class UnitWithOmni extends Node:
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var stats
	var buffs
	var _hp_stat_id: int = -1

	func get_speed() -> float:
		# 设计约定：速度来自 stats 的 SPEED
		if stats == null:
			return 0.0
		if not stats.has_method("get_final"):
			return 0.0
		# SPEED stat 可能在 RED 阶段缺失，用测试断言锁定
		return 0.0

	func is_dead() -> bool:
		if stats == null:
			return false
		if _hp_stat_id < 0:
			return false
		if not stats.has_method("get_final"):
			return false
		return float(stats.call("get_final", _hp_stat_id)) <= 0.0


func test_battle_started_triggers_hero_haste_passive_and_outspeeds_boss() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds = loaded.ds
	var enums_rt = loaded.enums_rt

	var speed_id = int(ds.stat_id("SPEED"))
	assert_true(speed_id >= 0, "SPEED stat must exist in rpg_tests/stat_defs.json")
	if speed_id < 0:
		return

	var hp_id = int(ds.stat_id("HP"))
	assert_true(hp_id >= 0)
	if hp_id < 0:
		return

	# 基础速度：Boss 最高；主角靠被动开战加速先手
	var hero_stats = OmniStatsComponent.new(6001, ds)
	var boss_stats = OmniStatsComponent.new(6002, ds)
	var hero_buffs = OmniBuffCore.new(ds, enums_rt)
	var boss_buffs = OmniBuffCore.new(ds, enums_rt)

	hero_stats.add_base(speed_id, 10.0 - float(hero_stats.get_final(speed_id)))
	boss_stats.add_base(speed_id, 12.0 - float(boss_stats.get_final(speed_id)))

	# 给 HP 一个正值，避免被判死
	hero_stats.add_base(hp_id, 100.0 - float(hero_stats.get_final(hp_id)))
	boss_stats.add_base(hp_id, 100.0 - float(boss_stats.get_final(hp_id)))

	var hero = UnitWithOmni.new()
	hero.entity_id = 6001
	hero.camp = "ally"
	hero.cell = Vector2i(0, 1)
	hero.stats = hero_stats
	hero.buffs = hero_buffs
	hero._hp_stat_id = hp_id

	var boss = UnitWithOmni.new()
	boss.entity_id = 6002
	boss.camp = "enemy"
	boss.cell = Vector2i(2, 1)
	boss.stats = boss_stats
	boss.buffs = boss_buffs
	boss._hp_stat_id = hp_id

	var units: Array[Node] = []
	units.assign([hero, boss])

	var runtime_dict = {
		"stats_by_entity": {6001: hero_stats, 6002: boss_stats},
		"buff_by_entity": {6001: hero_buffs, 6002: boss_buffs},
	}

	# TurnSkillRuntime 必须存在（autoload）；被动监听 event_bus
	assert_true(has_node("/root/TurnSkillRuntime"))
	var rt = get_node("/root/TurnSkillRuntime")
	if rt.has_method("ensure_ready"):
		rt.ensure_ready()
	rt.grid.set_units(units)
	rt.omnibuff.setup(ds, enums_rt, runtime_dict)
	rt.passive_manager.register_unit_passives(hero, ["pas_hero_battle_haste"])

	var ctx = BattleContext.new()
	ctx.build_from_autoload()
	ctx.dataset = ds
	ctx.enums_rt = enums_rt
	ctx.runtime_dict = runtime_dict

	var tm = TurnManager.new()
	tm.setup(ctx, units)

	var hero_spd0 = float(hero_stats.get_final(speed_id))
	var boss_spd0 = float(boss_stats.get_final(speed_id))
	assert_true(boss_spd0 > hero_spd0, "Baseline speed should be Boss > Hero")

	# 期望：start_battle() 会通过 event_bus emit battle_started，触发主角被动 apply SPEED buff
	tm.start_battle()

	var hero_spd1 = float(hero_stats.get_final(speed_id))
	var boss_spd1 = float(boss_stats.get_final(speed_id))
	assert_true(hero_spd1 > boss_spd1, "After battle_started passive, Hero should outspeed Boss")

	tm.stop_battle()
	hero.free()
	boss.free()
	tm.free()

