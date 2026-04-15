extends GutTest

const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_while_condition_hp_threshold_toggles_active() -> void:
	var loaded: Dictionary = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded["ds"]
	var enums_rt: OmniEnumsRuntime = loaded["enums_rt"]
	var pipe: OmniDamagePipeline = OmniDamagePipeline.new()
	var turn: OmniTurnComponent = OmniTurnComponent.new()

	var eid: int = 7401
	var e: Dictionary = TestBattle.make_entity(eid, ds, enums_rt)
	var runtime: Dictionary = TestBattle.make_runtime([e])
	var ids: PackedInt32Array = PackedInt32Array([eid])
	ids.sort()

	var hp_id: int = ds.stat_id("HP")
	var atk_id: int = ds.stat_id("ATK")

	var stats: OmniStatsComponent = e["stats"]
	var buffs: OmniBuffCore = e["buffs"]

	# 初始 HP=100，施加后应 inactive（ATK 不变）
	buffs.apply_buff(stats, "buff_cond_hp_le_50_atk_up_10", 111)
	assert_eq(float(stats.get_final(atk_id)), 10.0)

	# 扣血到 50，下一次 turn_start tick 后应 active（ATK +10）
	stats.add_base(hp_id, -50.0)
	turn.on_turn_start(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, null)
	assert_eq(float(stats.get_final(atk_id)), 20.0)

	# 回血到 60，下一次 turn_start tick 后应 inactive（ATK 回退）
	stats.add_base(hp_id, 10.0)
	turn.on_turn_start(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, null)
	assert_eq(float(stats.get_final(atk_id)), 10.0)


func test_while_condition_inactive_still_expires() -> void:
	var loaded: Dictionary = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded["ds"]
	var enums_rt: OmniEnumsRuntime = loaded["enums_rt"]
	var pipe: OmniDamagePipeline = OmniDamagePipeline.new()
	var turn: OmniTurnComponent = OmniTurnComponent.new()

	var eid: int = 7402
	var e: Dictionary = TestBattle.make_entity(eid, ds, enums_rt)
	var runtime: Dictionary = TestBattle.make_runtime([e])
	var ids: PackedInt32Array = PackedInt32Array([eid])
	ids.sort()

	var stats: OmniStatsComponent = e["stats"]
	var buffs: OmniBuffCore = e["buffs"]

	# 初始 HP=100（条件不满足），但 buff 是 2 回合到期
	buffs.apply_buff(stats, "buff_cond_hp_le_50_atk_up_10_2t", 111)
	assert_eq(int(buffs.inst_ids.size()), 1)

	turn.on_turn_end(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, null) # 2->1
	assert_eq(int(buffs.inst_ids.size()), 1)
	turn.on_turn_end(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, null) # 1->0 到期
	assert_eq(int(buffs.inst_ids.size()), 0)
