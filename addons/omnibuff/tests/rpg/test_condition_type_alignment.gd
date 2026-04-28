extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const Validate = preload("res://addons/omnibuff/config/compiler/validators.gd")


func _has_issue(issues: Array, level: int, contains: String) -> bool:
	for i in issues:
		if int(i.level) == level and String(i.message).find(contains) >= 0:
			return true
	return false


func test_condition_type_stat_threshold_in_enums() -> void:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var enums: Dictionary = res.enums.get("enums", {})
	var condition_types: Array = enums.get("condition_type", [])
	assert_true(condition_types.has("STAT_THRESHOLD"), "enums.condition_type must contain STAT_THRESHOLD")


func test_condition_type_equip_set_count_ge_in_enums() -> void:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var enums: Dictionary = res.enums.get("enums", {})
	var condition_types: Array = enums.get("condition_type", [])
	assert_true(condition_types.has("EQUIP_SET_COUNT_GE"), "enums.condition_type must contain EQUIP_SET_COUNT_GE")


func test_condition_type_values_in_buff_defs_are_valid() -> void:
	var manifest_path: String = "res://data/rpg_tests/manifest.json"
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full(manifest_path, true)
	var issues: Array = Validate.validate_all(manifest_path, res.manifest, res.enums, res.sources, true)
	assert_false(_has_issue(issues, OmniValidate.Level.ERROR, "unknown condition_type"),
		"no unknown condition_type errors in rpg_tests dataset")


func test_invalid_condition_type_caught_in_strict() -> void:
	var manifest_path: String = "res://data/rpg_tests/manifest.json"
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full(manifest_path, true)
	var sources: Dictionary = res.sources.duplicate(true)
	var buff_defs: Dictionary = sources["buff_defs"]
	var buffs: Array = buff_defs.get("buffs", [])

	var found := false
	for b in buffs:
		var conds: Array = (b as Dictionary).get("conditions", [])
		if not conds.is_empty():
			(b as Dictionary)["conditions"] = [{"condition_type": "INVALID_TYPE", "stat": "HP", "op": "LE", "value": 50.0}]
			found = true
			break

	if not found:
		var fake_buff := {"id": "buff_test_invalid_cond", "buff_type": "EXPLICIT", "tags": ["BUFF"],
			"duration": {"type": "PERMANENT"}, "stack": {"mode": "REPLACE", "max_stack": 1},
			"effects": [], "triggers": [],
			"conditions": [{"condition_type": "INVALID_TYPE", "stat": "HP", "op": "LE", "value": 50.0}]}
		buffs.append(fake_buff)

	var issues: Array = Validate.validate_all(manifest_path, res.manifest, res.enums, sources, true)
	assert_true(_has_issue(issues, OmniValidate.Level.ERROR, "unknown condition_type"),
		"strict mode must report error for invalid condition_type")


func test_base_demo_loads_without_condition_type_errors() -> void:
	var manifest_path: String = "res://data/base_demo/manifest.json"
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full(manifest_path, true)
	var issues: Array = Validate.validate_all(manifest_path, res.manifest, res.enums, res.sources, true)
	assert_false(_has_issue(issues, OmniValidate.Level.ERROR, "condition_type"),
		"base_demo must have no condition_type errors")
