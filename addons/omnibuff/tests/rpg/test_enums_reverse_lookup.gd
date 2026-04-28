extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")


func _make_enums_rt() -> OmniEnumsRuntime:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	return OmniEnumsRuntime.from_enums_json(res.enums)


func test_reverse_name_op_type() -> void:
	var rt := _make_enums_rt()
	assert_eq(rt.reverse_name("op_type", 0), "ADD")
	assert_eq(rt.reverse_name("op_type", 1), "MUL")
	assert_eq(rt.reverse_name("op_type", 2), "OVERRIDE")


func test_reverse_name_unknown_returns_empty() -> void:
	var rt := _make_enums_rt()
	assert_eq(rt.reverse_name("op_type", 999), "")
	assert_eq(rt.reverse_name("nonexistent_enum", 0), "")


func test_reverse_name_roundtrip() -> void:
	var rt := _make_enums_rt()
	var enum_name := "buff_type"
	for val in ["EXPLICIT", "IMPLICIT", "PASSIVE", "AURA"]:
		var code := rt.enum_int(enum_name, val)
		assert_gt(code, -1, "enum_int should find %s" % val)
		assert_eq(rt.reverse_name(enum_name, code), val, "roundtrip failed for %s" % val)


func test_reverse_name_event_phase() -> void:
	var rt := _make_enums_rt()
	assert_eq(rt.reverse_name("event_phase", 0), "BUILD")
	assert_eq(rt.reverse_name("event_phase", 1), "BEFORE_DEAL")


func test_enum_int_and_reverse_consistent() -> void:
	var rt := _make_enums_rt()
	var enum_name := "action_kind"
	var table: Dictionary = rt.enum_tables.get(enum_name, {})
	for val_str in table.keys():
		var code: int = int(table[val_str])
		assert_eq(rt.reverse_name(enum_name, code), String(val_str))
