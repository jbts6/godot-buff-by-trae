extends RefCounted
class_name TargetingRegistry

const FirstEnemyTargeting := preload("res://addons/turn_skill_system/runtime/targeting/first_enemy_targeting.gd")
const AllEnemiesTargeting := preload("res://addons/turn_skill_system/runtime/targeting/all_enemies_targeting.gd")
const SingleCellTargeting := preload("res://addons/turn_skill_system/runtime/targeting/single_cell_targeting.gd")
const CrossTargeting := preload("res://addons/turn_skill_system/runtime/targeting/cross_targeting.gd")

var _rules: Dictionary = {} # rule_id -> handler

func register_defaults() -> void:
	register_rule("first_enemy", FirstEnemyTargeting.new())
	register_rule("all_enemies", AllEnemiesTargeting.new())
	register_rule("single_cell", SingleCellTargeting.new())
	register_rule("cross", CrossTargeting.new())

func register_rule(rule_id: String, handler: RefCounted) -> void:
	_rules[rule_id] = handler

func resolve(skill: Dictionary, caster, primary_cell, grid, extra: Dictionary) -> Array[Dictionary]:
	if not skill.has("targeting"):
		return []

	var targeting = skill["targeting"]
	if typeof(targeting) == TYPE_STRING:
		var s := String(targeting)
		if s == "FIRST":
			return _resolve_rule("first_enemy", skill, caster, primary_cell, grid, extra)
		if s == "ALL":
			return _resolve_rule("all_enemies", skill, caster, primary_cell, grid, extra)
		return []

	if typeof(targeting) == TYPE_DICTIONARY:
		var rule_id := String(targeting.get("rule", ""))
		return _resolve_rule(rule_id, skill, caster, primary_cell, grid, extra)

	return []

func _resolve_rule(rule_id: String, skill: Dictionary, caster, primary_cell, grid, extra: Dictionary) -> Array[Dictionary]:
	if not _rules.has(rule_id):
		return []
	var h = _rules[rule_id]
	return h.resolve(skill, caster, primary_cell, grid, extra)

