extends GutTest

const SkillRuntime := preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")


class UnitWithId:
	extends RefCounted
	var entity_id: int = 123


class UnitNoId:
	extends RefCounted
	var foo: int = 1


func test_safe_id_returns_entity_id_and_does_not_crash() -> void:
	var u1 = UnitWithId.new()
	assert_eq(SkillRuntime._safe_id(u1), 123)

	var u2 = UnitNoId.new()
	assert_eq(SkillRuntime._safe_id(u2), -1)

