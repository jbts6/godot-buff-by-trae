extends GutTest

const SkillValidator := preload("res://addons/turn_skill_system/runtime/skill_validator.gd")


func test_active_requires_on_cast_and_on_hit() -> void:
	var skill := {
		"version": 1,
		"id": "act_x",
		"type": "active",
		"name": "x",
		"targeting": "FIRST",
	}
	var issues := SkillValidator.validate_skill(skill, "res://dummy.json", true)
	# strict: missing on_cast/on_hit => errors
	assert_true(issues.size() >= 2)


func test_normalize_active_migrates_legacy_effects_to_on_cast() -> void:
	var skill := {
		"version": 1,
		"id": "act_x",
		"type": "active",
		"name": "x",
		"targeting": "FIRST",
		"effects": [{"kind": "apply_buff", "params": {"buff_id": "buff_atk_flat_20"}}]
	}
	SkillValidator.normalize_active_in_place(skill)
	assert_true(skill.has("on_cast"))
	assert_true(typeof(skill.on_cast) == TYPE_ARRAY)
	assert_eq(skill.on_cast.size(), 1)
	assert_true(skill.has("on_hit"))
	assert_true(typeof(skill.on_hit) == TYPE_ARRAY)

