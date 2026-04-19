extends GutTest

const Grid = preload("res://addons/turn_skill_system/runtime/grid.gd")

class DummyUnit extends Node:
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var _dead: bool = false
	
	func _init(p_id: int, p_camp: String, p_cell: Vector2i, p_dead: bool) -> void:
		entity_id = p_id
		camp = p_camp
		cell = p_cell
		_dead = p_dead
	
	func is_dead() -> bool:
		return _dead


func test_grid_first_enemy_skips_dead_units() -> void:
	# 目的：锁定 FIRST targeting 的关键行为：
	# TurnSkillSystem 的 Grid.get_first_enemy() 必须跳过 is_dead()==true 的目标，
	# 否则会一直选到已死目标，导致战斗无法结束。
	var grid = Grid.new()
	
	var caster = DummyUnit.new(1001, "ally", Vector2i(2, 1), false)
	var dead_enemy = DummyUnit.new(2001, "enemy", Vector2i(0, 0), true)
	var alive_enemy = DummyUnit.new(2002, "enemy", Vector2i(0, 1), false)
	
	grid.set_units([caster, dead_enemy, alive_enemy])
	
	var picked = grid.get_first_enemy(caster)
	assert_eq(picked, alive_enemy, "应跳过死亡单位，选择下一个存活敌人")
	
	caster.free()
	dead_enemy.free()
	alive_enemy.free()
