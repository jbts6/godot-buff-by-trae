extends GutTest

const TurnCommand = preload("res://addons/turn_manager/runtime/turn_command.gd")


func test_turn_command_item_kind() -> void:
	assert_true(TurnCommand.has_method("new_item"), "TurnCommand should provide new_item(item_id, cell)")
	if not TurnCommand.has_method("new_item"):
		return

	var cmd = TurnCommand.new_item("item_potion_small", Vector2i(0, 0))
	assert_eq(String(cmd.kind), "item")
	assert_eq(String(cmd.id), "item_potion_small")
	assert_eq(Vector2i(cmd.primary_cell), Vector2i(0, 0))

