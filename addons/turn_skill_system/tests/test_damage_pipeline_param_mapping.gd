extends GutTest

const SkillRuntime = preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid = preload("res://addons/turn_skill_system/runtime/grid.gd")
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

func test_damage_meta_exposes_mapped_params() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt = loaded.enums_rt
	var ds = loaded.ds

	var a_stats = OmniStatsComponent.new(5001, ds)
	var t_stats = OmniStatsComponent.new(5002, ds)
	var a_buffs = OmniBuffCore.new(ds, enums_rt)
	var t_buffs = OmniBuffCore.new(ds, enums_rt)
	var caster = UnitWithOmni.new(5001, "ally", Vector2i(2, 1), a_stats, a_buffs)
	var target = UnitWithOmni.new(5002, "enemy", Vector2i(0, 1), t_stats, t_buffs)

	var grid = Grid.new()
	grid.set_units([caster, target])
	var runtime_dict = {"stats_by_entity": {5001: a_stats, 5002: t_stats}, "buff_by_entity": {5001: a_buffs, 5002: t_buffs}}

	var r = SkillRuntime.cast("act_demo_single", caster, null, {
		"grid": grid,
		"dataset": ds,
		"enums_rt": enums_rt,
		"runtime_dict": runtime_dict,
		"turn_index": 7,
		"roll_key": 42,
		"tags": ["BASIC_ATTACK"],
		"damage_type": "PHYSICAL",
		"element": "NONE",
		"is_bonus_damage": true,
	})
	assert_true(bool(r.get("ok", false)))

	var dmg_meta = {}
	for e in r.get("effects", []):
		if String(e.get("kind","")) == "damage":
			dmg_meta = e.get("meta", {})
	print("dmg_meta: ", dmg_meta)
	assert_true(not dmg_meta.is_empty())
	assert_eq(int(dmg_meta.get("turn_index", -1)), 7)
	assert_eq(int(dmg_meta.get("roll_key", -1)), 42)
	assert_true(int(dmg_meta.get("tags_mask", 0)) != 0)
	assert_true(bool(dmg_meta.get("is_bonus_damage", false)))