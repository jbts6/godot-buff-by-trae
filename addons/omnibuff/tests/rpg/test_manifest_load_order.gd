extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")


func test_load_order_respected_in_base_demo() -> void:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", true)
	var load_order: Array = res.manifest.get("load_order", [])
	assert_gt(load_order.size(), 0, "base_demo should have load_order")
	assert_eq(String(load_order[0]), "enums", "enums should be first in load_order")
	assert_eq(String(load_order[1]), "stat_defs", "stat_defs should be second")


func test_load_order_respected_in_rpg_tests() -> void:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var load_order: Array = res.manifest.get("load_order", [])
	assert_gt(load_order.size(), 0, "rpg_tests should have load_order")


func test_sort_by_load_order_produces_correct_sequence() -> void:
	var files := [
		{"type": "buff_defs", "path": "b.json"},
		{"type": "stat_defs", "path": "a.json"},
		{"type": "skill_defs", "path": "c.json"},
	]
	var load_order := ["stat_defs", "buff_defs", "skill_defs"]
	var sorted := OmniManifestLoader._sort_by_load_order(files, load_order)
	assert_eq(String(sorted[0].get("type", "")), "stat_defs")
	assert_eq(String(sorted[1].get("type", "")), "buff_defs")
	assert_eq(String(sorted[2].get("type", "")), "skill_defs")


func test_sort_by_load_order_unknown_types_go_last() -> void:
	var files := [
		{"type": "unknown_type", "path": "x.json"},
		{"type": "stat_defs", "path": "a.json"},
		{"type": "buff_defs", "path": "b.json"},
	]
	var load_order := ["stat_defs", "buff_defs"]
	var sorted := OmniManifestLoader._sort_by_load_order(files, load_order)
	assert_eq(String(sorted[0].get("type", "")), "stat_defs")
	assert_eq(String(sorted[1].get("type", "")), "buff_defs")
	assert_eq(String(sorted[2].get("type", "")), "unknown_type")


func test_sort_by_load_order_empty_order_returns_original() -> void:
	var files := [
		{"type": "buff_defs", "path": "b.json"},
		{"type": "stat_defs", "path": "a.json"},
	]
	var sorted := OmniManifestLoader._sort_by_load_order(files, [])
	assert_eq(String(sorted[0].get("type", "")), "buff_defs")
	assert_eq(String(sorted[1].get("type", "")), "stat_defs")
