class_name BattleContext
extends RefCounted

## 必需字段
var grid: Object
var event_bus: Object
var dataset: Resource
var enums_rt: Resource
var runtime_dict: Dictionary
var turn_component: Object
var omnibuff_adapter: Object
var passive_manager: Object
var aura_manager: Object

## 可选字段
var pipeline: Object
var replay: Object

func _init() -> void:
	runtime_dict = {
		"stats_by_entity": {},
		"buff_by_entity": {}
	}
	# 默认实例化组件
	if ClassDB.class_exists("OmniTurnComponent"):
		turn_component = ClassDB.instantiate("OmniTurnComponent")
	else:
		# Fallback if class_name not registered yet in some contexts
		var script = load("res://addons/omnibuff/runtime/components/turn_component.gd")
		if script:
			turn_component = script.new()

	var pipeline_path = "res://addons/omnibuff/runtime/core/damage_pipeline.gd"
	if FileAccess.file_exists(pipeline_path):
		var pipeline_script = load(pipeline_path)
		if pipeline_script:
			pipeline = pipeline_script.new()

func build_from_autoload() -> void:
	var root = Engine.get_main_loop().root
	if root.has_node("TurnSkillRuntime"):
		var skill_rt = root.get_node("TurnSkillRuntime")
		if skill_rt.has_method("ensure_ready"):
			skill_rt.ensure_ready()
		grid = skill_rt.get("grid")
		event_bus = skill_rt.get("event_bus")
		omnibuff_adapter = skill_rt.get("omnibuff")
		passive_manager = skill_rt.get("passive_manager")
		aura_manager = skill_rt.get("aura_manager")

func validate() -> bool:
	if not grid:
		push_error("[TurnManager] BattleContext validation failed: missing grid")
		return false
	if not event_bus:
		push_error("[TurnManager] BattleContext validation failed: missing event_bus")
		return false
	if not dataset:
		push_error("[TurnManager] BattleContext validation failed: missing dataset(ds). It must be provided manually by business logic.")
		return false
	if not enums_rt:
		push_error("[TurnManager] BattleContext validation failed: missing enums_rt. It must be provided manually by business logic.")
		return false
	if not runtime_dict or typeof(runtime_dict) != TYPE_DICTIONARY:
		push_error("[TurnManager] BattleContext validation failed: missing or invalid runtime_dict")
		return false
	if not turn_component:
		push_error("[TurnManager] BattleContext validation failed: missing turn_component")
		return false
	if not omnibuff_adapter:
		push_error("[TurnManager] BattleContext validation failed: missing omnibuff_adapter")
		return false
	return true
