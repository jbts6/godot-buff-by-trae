extends GutTest

const TurnManager = preload("res://addons/turn_manager/runtime/turn_manager.gd")


func test_cooldown_decrements_and_clears() -> void:
	var tm = TurnManager.new()

	assert_true(tm.has_method("_set_skill_cooldown"), "TurnManager should provide _set_skill_cooldown(eid, skill_id, turns)")
	assert_true(tm.has_method("_get_skill_cooldown"), "TurnManager should provide _get_skill_cooldown(eid, skill_id)")
	assert_true(tm.has_method("_tick_skill_cooldowns"), "TurnManager should provide _tick_skill_cooldowns(eid)")
	if not (tm.has_method("_set_skill_cooldown") and tm.has_method("_get_skill_cooldown") and tm.has_method("_tick_skill_cooldowns")):
		tm.free()
		return

	tm.call("_set_skill_cooldown", 1, "act_aoe", 2)
	assert_eq(int(tm.call("_get_skill_cooldown", 1, "act_aoe")), 2)

	tm.call("_tick_skill_cooldowns", 1)
	assert_eq(int(tm.call("_get_skill_cooldown", 1, "act_aoe")), 1)

	tm.call("_tick_skill_cooldowns", 1)
	assert_eq(int(tm.call("_get_skill_cooldown", 1, "act_aoe")), 0, "Cooldown should clear when it reaches 0")

	tm.free()


func test_choose_skill_falls_back_to_basic_when_all_on_cooldown() -> void:
	var tm = TurnManager.new()

	assert_true(tm.has_method("_choose_skill_with_cooldown"), "TurnManager should provide _choose_skill_with_cooldown(eid, preferred, basic)")
	if not tm.has_method("_choose_skill_with_cooldown"):
		tm.free()
		return

	tm.call("_set_skill_cooldown", 1, "act_aoe", 2)
	tm.call("_set_skill_cooldown", 1, "act_big", 1)

	var chosen = String(tm.call("_choose_skill_with_cooldown", 1, ["act_aoe", "act_big"], "act_basic"))
	assert_eq(chosen, "act_basic")

	tm.free()

