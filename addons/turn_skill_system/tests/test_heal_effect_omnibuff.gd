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

func test_heal_effect_applies_and_emits_events() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt = loaded.enums_rt
	var ds = loaded.ds

	var a_stats = OmniStatsComponent.new(4001, ds)
	var t_stats = OmniStatsComponent.new(4002, ds)
	var a_buffs = OmniBuffCore.new(ds, enums_rt)
	var t_buffs = OmniBuffCore.new(ds, enums_rt)

	var caster = UnitWithOmni.new(4001, "ally", Vector2i(2, 1), a_stats, a_buffs)
	var target = UnitWithOmni.new(4002, "ally", Vector2i(1, 1), t_stats, t_buffs)

	var grid = Grid.new()
	grid.set_units([caster, target])

	var runtime_dict = {"stats_by_entity": {4001: a_stats, 4002: t_stats}, "buff_by_entity": {4001: a_buffs, 4002: t_buffs}}

	var hp_id = int(ds.stat_id_to_int.get("HP", -1))
	t_stats.add_base(hp_id, 10.0 - t_stats.get_final(hp_id))

	var r = SkillRuntime.cast("act_demo_heal", caster, Vector2i(1, 1), {
		"grid": grid,
		"dataset": ds,
		"enums_rt": enums_rt,
		"runtime_dict": runtime_dict,
		"turn_index": 1
	})

	var is_ok = bool(r.get("ok", false))
	if not is_ok:
		print("CAST FAILED: ", r)
	assert_true(is_ok)
	var has_heal = false
	for e in r.get("effects", []):
		if String(e.get("kind","")) == "heal":
			has_heal = true
	assert_true(has_heal)

	var types: Array[String] = []
	for ev in r.get("events", []):
		types.append(String(ev.get("type","")))
	assert_true(types.has("before_heal"))
	assert_true(types.has("after_heal"))
	
	# Assert HP increased
	assert_true(t_stats.get_final(hp_id) > 10.0, "HP should have increased")