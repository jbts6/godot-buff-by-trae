extends GutTest

const SBM = preload("res://addons/omni_set_bonuses/runtime/set_bonus_manager.gd")


class FakeStats:
	var entity_id: int
	func _init(eid: int) -> void:
		entity_id = eid


class FakeBuffCore:
	var applied: Array[String] = []
	var removed: Array[String] = []
	var active: Dictionary = {} # buff_id -> true

	func apply_buff(_stats, buff_id: String, _source_id: int) -> int:
		if not active.has(buff_id):
			applied.append(buff_id)
		active[buff_id] = true
		return 1

	func remove_by_buff_id(_stats, buff_id: String, _scope: String = "ALL", _source_id: int = -1, _include_implicit: bool = false, _force: bool = false) -> int:
		if active.has(buff_id):
			active.erase(buff_id)
			removed.append(buff_id)
			return 1
		return 0


func test_compute_active_buffs() -> void:
	var items: Array = [
		{"item_id": "a", "set_id": "dragon"},
		{"item_id": "b", "set_id": "dragon"},
		{"item_id": "c", "set_id": "dragon"},
		{"item_id": "d", "set_id": "dragon"}
	]
	var defs: Dictionary = {"dragon": {2: "set_dragon_2pc", 4: "set_dragon_4pc"}}

	var out: PackedStringArray = SBM.compute_active_set_buffs(items, defs)
	assert_true(out.has("set_dragon_2pc"))
	assert_true(out.has("set_dragon_4pc"))


func test_refresh_is_idempotent_and_diffs() -> void:
	var items4: Array = [
		{"item_id": "a", "set_id": "dragon"},
		{"item_id": "b", "set_id": "dragon"},
		{"item_id": "c", "set_id": "dragon"},
		{"item_id": "d", "set_id": "dragon"}
	]
	var items2: Array = [
		{"item_id": "a", "set_id": "dragon"},
		{"item_id": "b", "set_id": "dragon"}
	]
	var defs: Dictionary = {"dragon": {2: "set_dragon_2pc", 4: "set_dragon_4pc"}}

	var mgr := SBM.new()
	var stats := FakeStats.new(1001)
	var buffs := FakeBuffCore.new()

	mgr.refresh_entity(stats, buffs, items4, defs, 1001)
	assert_eq(buffs.applied.size(), 2)

	# second call: idempotent (no new applies)
	mgr.refresh_entity(stats, buffs, items4, defs, 1001)
	assert_eq(buffs.applied.size(), 2)

	# downgrade to 2pc: remove 4pc only
	mgr.refresh_entity(stats, buffs, items2, defs, 1001)
	assert_true(buffs.removed.has("set_dragon_4pc"))
	assert_false(buffs.removed.has("set_dragon_2pc"))

