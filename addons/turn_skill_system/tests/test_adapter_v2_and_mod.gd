extends GutTest

const OmniBuffAdapter = preload("res://addons/turn_skill_system/runtime/omni_buff_adapter.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")

class UnitWithOmni:
	extends RefCounted
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var stats
	var buffs
	func _init(eid: int, c: String, p: Vector2i, s, b) -> void:
		entity_id = eid
		camp = c
		cell = p
		stats = s
		buffs = b

func test_adapter_uses_v2_when_available() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt = loaded.enums_rt
	var ds = loaded.ds

	var a_stats = OmniStatsComponent.new(6001, ds)
	var t_stats = OmniStatsComponent.new(6002, ds)
	var a_buffs = OmniBuffCore.new(ds, enums_rt)
	var t_buffs = OmniBuffCore.new(ds, enums_rt)
	var caster = UnitWithOmni.new(6001, "ally", Vector2i(2, 1), a_stats, a_buffs)
	var target = UnitWithOmni.new(6002, "enemy", Vector2i(0, 1), t_stats, t_buffs)

	var adapter = OmniBuffAdapter.new()
	var runtime_dict = {"stats_by_entity": {6001: a_stats, 6002: t_stats}, "buff_by_entity": {6001: a_buffs, 6002: t_buffs}}
	adapter.setup(ds, enums_rt, runtime_dict)

	var r = adapter.deal_damage(caster, target, 20.0, {
		"turn_index": 1,
		"roll_key": 0,
		"rng_seed": 12345,
	})
	assert_true(bool(r.get("ok", false)))
	var meta = r.get("meta", {})
	assert_eq(String(meta.get("used", "")), "deal_damage_v2")
	assert_eq(int(meta.get("rng_seed", -1)), 12345)

func test_adapter_v2_deterministic_same_seed() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt = loaded.enums_rt
	var ds = loaded.ds

	var results: Array = []
	for i in range(2):
		var a_stats = OmniStatsComponent.new(7001, ds)
		var t_stats = OmniStatsComponent.new(7002, ds)
		var a_buffs = OmniBuffCore.new(ds, enums_rt)
		var t_buffs = OmniBuffCore.new(ds, enums_rt)
		var caster = UnitWithOmni.new(7001, "ally", Vector2i(2, 1), a_stats, a_buffs)
		var target = UnitWithOmni.new(7002, "enemy", Vector2i(0, 1), t_stats, t_buffs)

		var adapter = OmniBuffAdapter.new()
		var runtime_dict = {"stats_by_entity": {7001: a_stats, 7002: t_stats}, "buff_by_entity": {7001: a_buffs, 7002: t_buffs}}
		adapter.setup(ds, enums_rt, runtime_dict)

		var r = adapter.deal_damage(caster, target, 30.0, {
			"turn_index": 3,
			"roll_key": 5,
			"rng_seed": 99999,
		})
		results.append(float(r.get("final_damage", -1.0)))

	assert_eq(results[0], results[1])

func test_adapter_mod_conflicts_flagged() -> void:
	var adapter = OmniBuffAdapter.new()
	adapter.setup(null, null, {}, [{"id": "buff_atk_flat_20", "replaced_by": "mod"}])
	var flagged = adapter.mod_conflicts.size() > 0
	assert_true(flagged)

func test_adapter_apply_buff_with_mod_flag() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt = loaded.enums_rt
	var ds = loaded.ds

	var t_stats = OmniStatsComponent.new(8001, ds)
	var t_buffs = OmniBuffCore.new(ds, enums_rt)
	var target = UnitWithOmni.new(8001, "ally", Vector2i(0, 0), t_stats, t_buffs)
	var source = UnitWithOmni.new(8002, "ally", Vector2i(1, 0), t_stats, OmniBuffCore.new(ds, enums_rt))

	var adapter = OmniBuffAdapter.new()
	var runtime_dict = {"stats_by_entity": {8001: t_stats}, "buff_by_entity": {8001: t_buffs}}
	adapter.setup(ds, enums_rt, runtime_dict, [{"id": "buff_atk_flat_20"}])

	var r = adapter.apply_buff(target, "buff_atk_flat_20", source)
	assert_true(bool(r.get("ok", false)))
	assert_true(bool(r.get("mod_overridden", false)))

func test_adapter_apply_buff_no_mod() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt = loaded.enums_rt
	var ds = loaded.ds

	var t_stats = OmniStatsComponent.new(9001, ds)
	var t_buffs = OmniBuffCore.new(ds, enums_rt)
	var target = UnitWithOmni.new(9001, "ally", Vector2i(0, 0), t_stats, t_buffs)
	var source = UnitWithOmni.new(9002, "ally", Vector2i(1, 0), t_stats, OmniBuffCore.new(ds, enums_rt))

	var adapter = OmniBuffAdapter.new()
	var runtime_dict = {"stats_by_entity": {9001: t_stats}, "buff_by_entity": {9001: t_buffs}}
	adapter.setup(ds, enums_rt, runtime_dict, [])

	var r = adapter.apply_buff(target, "buff_atk_flat_20", source)
	assert_true(bool(r.get("ok", false)))
	assert_false(bool(r.get("mod_overridden", true)))
