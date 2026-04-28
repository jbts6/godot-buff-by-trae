extends GutTest

const BattleNarrator = preload("res://addons/turn_manager/runtime/battle_narrator.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")

func test_buff_name_uses_indexed_lookup() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds = loaded.ds

	var narrator = BattleNarrator.new()
	narrator.bind(null, null, ds, null, {})

	var name = narrator._buff_name("buff_atk_flat_20")
	assert_ne(name, "buff_atk_flat_20")

func test_buff_name_unknown_returns_id() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds = loaded.ds

	var narrator = BattleNarrator.new()
	narrator.bind(null, null, ds, null, {})

	var name = narrator._buff_name("nonexistent_buff_xyz")
	assert_eq(name, "nonexistent_buff_xyz")

func test_buff_name_empty_returns_question() -> void:
	var narrator = BattleNarrator.new()
	narrator.bind(null, null, null, null, {})

	var name = narrator._buff_name("")
	assert_eq(name, "?")

func test_buff_name_no_dataset_returns_id() -> void:
	var narrator = BattleNarrator.new()
	narrator.bind(null, null, null, null, {})

	var name = narrator._buff_name("buff_atk_flat_20")
	assert_eq(name, "buff_atk_flat_20")

func test_buff_name_consistent_with_linear_scan() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds = loaded.ds

	var narrator = BattleNarrator.new()
	narrator.bind(null, null, ds, null, {})

	var indexed_name = narrator._buff_name("buff_atk_flat_20")

	var linear_name = "buff_atk_flat_20"
	var defs_any = ds.get("buff_defs")
	if typeof(defs_any) == TYPE_ARRAY:
		for d_any in defs_any:
			if typeof(d_any) == TYPE_DICTIONARY and String(d_any.get("id", "")) == "buff_atk_flat_20":
				var n = String(d_any.get("name", ""))
				if n != "":
					linear_name = n
				break

	assert_eq(indexed_name, linear_name)
