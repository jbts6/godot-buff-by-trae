extends GutTest

const BattleEventBus = preload("res://addons/turn_skill_system/runtime/battle_event_bus.gd")


class FakeStats extends RefCounted:
	var hp: float = 0.0
	var max_hp: float = 0.0
	func get_final(_sid: int) -> float:
		# 0=HP, 1=MAX_HP
		if _sid == 0:
			return hp
		if _sid == 1:
			return max_hp
		return 0.0
	func add_base(_sid: int, delta: float) -> void:
		if _sid == 0:
			hp += delta


class FakeDataset extends RefCounted:
	func stat_id(name: String) -> int:
		if name == "HP": return 0
		if name == "MAX_HP": return 1
		return -1


class FakeUnit extends Node:
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var stats: FakeStats


class FakeInventory extends RefCounted:
	var counts: Dictionary = {}
	func set_count(item_id: String, n: int) -> void:
		counts[item_id] = n
	func get_count(item_id: String) -> int:
		return int(counts.get(item_id, 0))
	func consume(item_id: String, amount: int) -> Dictionary:
		var cur = get_count(item_id)
		if cur < amount:
			return {"ok": false, "error": "not_enough"}
		counts[item_id] = cur - amount
		return {"ok": true}


class FakeOmniBuffAdapter extends RefCounted:
	var ds: FakeDataset
	var runtime_dict: Dictionary
	func heal(_caster: Node, target: Node, amount: float, _ctx: Dictionary) -> Dictionary:
		var sid_hp = int(ds.stat_id("HP"))
		var sid_max = int(ds.stat_id("MAX_HP"))
		var st: FakeStats = runtime_dict["stats_by_entity"][int(target.entity_id)]
		var before = float(st.get_final(sid_hp))
		var maxhp = float(st.get_final(sid_max))
		var after = min(before + amount, maxhp)
		st.add_base(sid_hp, after - before)
		return {"ok": true, "final_heal": after - before, "meta": {}}


func test_use_item_emits_after_heal_and_consumes() -> void:
	var battle_item_system_script = load("res://addons/turn_manager/runtime/items/battle_item_system.gd")
	assert_true(battle_item_system_script != null, "BattleItemSystem script should exist")
	if battle_item_system_script == null:
		return

	var bus = BattleEventBus.new()
	bus.begin_capture()

	var ds = FakeDataset.new()
	var runtime_dict := {"stats_by_entity": {}, "buff_by_entity": {}}

	var hero = FakeUnit.new()
	hero.entity_id = 1
	hero.camp = "ally"
	hero.cell = Vector2i(0, 0)
	hero.stats = FakeStats.new()
	hero.stats.hp = 50
	hero.stats.max_hp = 100
	runtime_dict["stats_by_entity"][1] = hero.stats

	var inv = FakeInventory.new()
	inv.set_count("item_potion_small", 1)

	var adapter = FakeOmniBuffAdapter.new()
	adapter.ds = ds
	adapter.runtime_dict = runtime_dict

	var item_db := {
		"item_potion_small": {
			"id": "item_potion_small",
			"name": "小治疗药水",
			"targeting": {"rule": "single_cell", "camp": "ally"},
			"effects": [
				{"kind": "heal", "params": {"amount": 35}}
			]
		}
	}

	var sys = battle_item_system_script.new()
	sys.bind(bus, adapter, inv, ds, runtime_dict, item_db)

	var r: Dictionary = sys.execute_item(1, "item_potion_small", Vector2i(0, 0))
	assert_true(bool(r.get("ok", false)), "execute_item should succeed")
	assert_eq(inv.get_count("item_potion_small"), 0, "Item should be consumed")
	assert_eq(int(hero.stats.get_final(0)), 85, "HP should increase by 35")

	var events: Array = bus.end_capture()
	var names: Array[String] = []
	for e in events:
		names.append(String(e.get("type", "")))
	assert_true("after_heal" in names, "Should emit after_heal")
	assert_true("item_used" in names, "Should emit item_used")

