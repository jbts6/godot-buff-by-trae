extends GutTest

const BattleEventBus = preload("res://addons/turn_skill_system/runtime/battle_event_bus.gd")


func test_battle_narrator_emits_semantic_lines() -> void:
	var narrator_script = load("res://addons/turn_manager/runtime/battle_narrator.gd")
	assert_true(narrator_script != null, "BattleNarrator script should exist")
	if narrator_script == null:
		return

	var bus = BattleEventBus.new()
	var narrator = narrator_script.new()

	var lines: Array[String] = []
	narrator.line_emitted.connect(func(bb: String, _meta: Dictionary):
		lines.append(bb)
	)

	narrator.bind(bus, null, null, null, {}, {1: "主角", 2: "Boss"}, {})

	bus.emit_event("battle_started", {})
	bus.emit_event("buff_applied", {"skill_id": "pas_hero_battle_haste", "caster_id": 1, "target_id": 1, "buff_id": "buff_hero_speed_flat_5_3t"})
	bus.emit_event("turn_order_computed", {"order": [
		{"eid": 1, "speed": 15.0},
		{"eid": 2, "speed": 12.0},
	]})
	bus.emit_event("turn_started", {"turn_index": 1, "actor_id": 1})
	bus.emit_event("action_started", {"turn_index": 1, "actor_id": 1, "skill_id": "act_hero_whirlwind"})
	bus.emit_event("after_damage", {"skill_id": "act_hero_whirlwind", "caster_id": 1, "target_id": 2, "final_damage": 50})
	bus.emit_event("unit_died", {"actor_id": 2})

	assert_true(lines.size() >= 3, "Narrator should emit multiple lines")
	assert_true(_any_contains(lines, "战斗开始"), "Should contain battle start line")
	assert_true(_any_contains(lines, "获得") or _any_contains(lines, "生效"), "Should contain buff applied line")
	assert_true(_any_contains(lines, "出手顺序"), "Should contain turn order line")
	assert_true(_any_contains(lines, "回合"), "Should contain turn line")
	assert_true(_any_contains(lines, "受到") or _any_contains(lines, "伤害"), "Should contain damage line")


func _any_contains(lines: Array[String], needle: String) -> bool:
	for s in lines:
		if needle in s:
			return true
	return false
