extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")


func _compile_base_demo() -> OmniCompiledDataset:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", true)
	var enums_rt := OmniEnumsRuntime.from_enums_json(res.enums)
	return OmniDatasetCompiler.compile(res.manifest, enums_rt, res.sources)


func _compile_rpg_tests() -> OmniCompiledDataset:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var enums_rt := OmniEnumsRuntime.from_enums_json(res.enums)
	return OmniDatasetCompiler.compile(res.manifest, enums_rt, res.sources)


func test_stat_id_mapping_base_demo() -> void:
	var ds := _compile_base_demo()
	assert_gt(ds.stat_id("ATK"), -1, "ATK should have valid stat_id")
	assert_gt(ds.stat_id("DEF"), -1, "DEF should have valid stat_id")
	assert_gt(ds.stat_id("HP"), -1, "HP should have valid stat_id")
	assert_eq(ds.stat_id("NONEXISTENT"), -1, "nonexistent stat should return -1")


func test_buff_id_mapping_base_demo() -> void:
	var ds := _compile_base_demo()
	assert_gt(ds.buff_id("buff_equip_weapon_001"), -1, "buff_equip_weapon_001 should have valid buff_id")
	assert_eq(ds.buff_id("NONEXISTENT"), -1, "nonexistent buff should return -1")


func test_skill_defs_compiled_rpg_tests() -> void:
	var ds := _compile_rpg_tests()
	assert_gt(ds.skill_defs.size(), 0, "skill_defs should not be empty")
	assert_gt(ds.skill_id("skill_triple_slash"), -1, "skill_triple_slash should have valid skill_id")
	assert_gt(ds.skill_id("skill_basic_attack_1"), -1, "skill_basic_attack_1 should have valid skill_id")
	assert_eq(ds.skill_id("NONEXISTENT"), -1, "nonexistent skill should return -1")


func test_skill_defs_compiled_base_demo() -> void:
	var ds := _compile_base_demo()
	assert_gt(ds.skill_defs.size(), 0, "skill_defs should not be empty in base_demo")


func test_equipment_defs_compiled_base_demo() -> void:
	var ds := _compile_base_demo()
	assert_gt(ds.equipment_defs.size(), 0, "equipment_defs should not be empty in base_demo")
	assert_gt(ds.equipment_id("equip_weapon_001"), -1, "equip_weapon_001 should have valid equipment_id")


func test_equipment_defs_empty_rpg_tests() -> void:
	var ds := _compile_rpg_tests()
	assert_eq(ds.equipment_defs.size(), 0, "equipment_defs should be empty in rpg_tests (no equipment file)")


func test_set_bonus_defs_compiled_base_demo() -> void:
	var ds := _compile_base_demo()
	assert_gt(ds.set_bonus_defs.size(), 0, "set_bonus_defs should not be empty in base_demo")


func test_set_bonus_defs_empty_rpg_tests() -> void:
	var ds := _compile_rpg_tests()
	assert_eq(ds.set_bonus_defs.size(), 0, "set_bonus_defs should be empty in rpg_tests")


func test_pipeline_stages_compiled() -> void:
	var ds := _compile_base_demo()
	assert_gt(ds.pipeline_stages.size(), 0, "pipeline_stages should not be empty")
	var ds2 := _compile_rpg_tests()
	assert_gt(ds2.pipeline_stages.size(), 0, "pipeline_stages should not be empty in rpg_tests")


func test_skill_defs_accessible_from_ds_in_battle_executor() -> void:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var enums_rt := OmniEnumsRuntime.from_enums_json(res.enums)
	var ds := OmniDatasetCompiler.compile(res.manifest, enums_rt, res.sources)
	assert_gt(ds.skill_defs.size(), 0)
	var skill: Dictionary = ds.skill_defs[0]
	assert_true(skill.has("id"), "skill def should have id field")
	assert_true(skill.has("base_damage"), "skill def should have base_damage field")
