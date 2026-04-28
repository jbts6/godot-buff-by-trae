extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const EnumsRuntime = preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")
const DatasetCompiler = preload("res://addons/omnibuff/config/compiler/dataset_compiler.gd")

var _ds = null
var _enums_rt = null


func before_all() -> void:
	var res = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	_enums_rt = EnumsRuntime.from_enums_json(res.enums)
	_ds = DatasetCompiler.compile(res.manifest, _enums_rt, res.sources)


func test_buff_defs_compiled_size_matches_raw() -> void:
	assert_eq(_ds.buff_defs_compiled.size(), _ds.buff_defs.size(), "compiled size should match raw size")


func test_compiled_buff_def_has_correct_id() -> void:
	for i in range(_ds.buff_defs.size()):
		var raw: Dictionary = _ds.buff_defs[i]
		var cbd = _ds.buff_defs_compiled[i]
		assert_eq(String(cbd.buff_id_str), String(raw.get("id", "")), "buff_id_str should match raw id at index %d" % i)


func test_compiled_effects_match_raw() -> void:
	var idx: int = _ds.buff_id("buff_atk_flat_20")
	assert_gte(idx, 0, "buff_atk_flat_20 should exist")
	var cbd = _ds.buff_defs_compiled[idx]
	var raw_effects: Array = _ds.buff_defs[idx].get("effects", [])
	assert_eq(cbd.effects.size(), raw_effects.size(), "effects count should match")
	if cbd.effects.size() > 0:
		var ce = cbd.effects[0]
		var re: Dictionary = raw_effects[0]
		assert_eq(float(ce.value), float(re.get("value", 0.0)), "effect value should match")
		assert_eq(String(ce.op_str), String(re.get("op", "")), "effect op_str should match")
		assert_eq(String(ce.phase_str), String(re.get("phase", "")), "effect phase_str should match")


func test_compiled_tag_mask_matches_runtime() -> void:
	var idx: int = _ds.buff_id("buff_dot_fire_3t")
	assert_gte(idx, 0, "buff_dot_fire_3t should exist")
	var cbd = _ds.buff_defs_compiled[idx]
	var raw_tags: Array = _ds.buff_defs[idx].get("tags", [])
	var expected_mask: int = _enums_rt.tag_mask(raw_tags)
	assert_eq(int(cbd.tag_mask), expected_mask, "compiled tag_mask should match runtime tag_mask")


func test_compiled_dot_fields() -> void:
	var idx: int = _ds.buff_id("buff_dot_fire_3t")
	assert_gte(idx, 0, "buff_dot_fire_3t should exist")
	var cbd = _ds.buff_defs_compiled[idx]
	assert_ne(cbd.dot, null, "dot should not be null for DOT buff")
	var raw_dot: Dictionary = _ds.buff_defs[idx].get("dot", {})
	assert_eq(float(cbd.dot.base_ratio), float(raw_dot.get("base_ratio", 0.0)), "dot base_ratio should match")
