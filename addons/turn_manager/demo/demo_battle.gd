extends Node

class DemoUnit extends Node:
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var speed: float
	var stats: RefCounted
	var buffs: RefCounted
	
	func _init(p_id: int, p_camp: String, p_cell: Vector2i, p_speed: float) -> void:
		entity_id = p_id
		camp = p_camp
		cell = p_cell
		speed = p_speed
		
	func get_speed() -> float:
		return speed
		
	func is_dead() -> bool:
		return false

var turn_manager: TurnManager

func _ready() -> void:
	print("--- TurnManager Demo Start ---")
	
	# Initialize components
	turn_manager = TurnManager.new()
	add_child(turn_manager)
	
	# Try to get context from autoload
	var context = BattleContext.new()
	context.build_from_autoload()
	
	# Create units
	var u1 = DemoUnit.new(1, "ally", Vector2i(0, 0), 10.0)
	var u2 = DemoUnit.new(2, "enemy", Vector2i(1, 0), 8.0)
	add_child(u1)
	add_child(u2)
	
	# Connect signals
	turn_manager.action_requested.connect(_on_action_requested)
	turn_manager.turn_started.connect(func(actor, index): print("[Demo] Turn started for entity %d (turn %d)" % [actor.entity_id, index]))
	turn_manager.turn_ended.connect(func(actor, index): print("[Demo] Turn ended for entity %d (turn %d)" % [actor.entity_id, index]))
	turn_manager.battle_ended.connect(func(res): print("[Demo] Battle ended: ", res))
	
	# Start battle
	print("[Demo] Setting up TurnManager...")
	# For demo to run standalone, we might need a mocked context or full dataset. 
	# Assuming user runs this when TurnSkillRuntime autoload is active.
	# We just do a simple setup and wait.
	
func _on_action_requested(actor: Node, valid_skills: Array) -> void:
	print("[Demo] Action requested for entity %d, submitting command..." % actor.entity_id)
	
	# Auto-submit a command
	var cmd = TurnCommand.new("strike", Vector2i(1, 0))
	turn_manager.submit_player_command(cmd)
