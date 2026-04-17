extends GutTest

const SkillDB := preload("res://addons/turn_skill_system/runtime/skill_db.gd")
const IndexBuilder := preload("res://addons/turn_skill_system/runtime/index_builder.gd")


func test_index_builder_rebuild_includes_demo_skills() -> void:
	var r := IndexBuilder.rebuild_index()
	assert_true(bool(r.get("ok", false)))
	var index: Dictionary = r.get("index", {})
	var skills: Array = index.get("skills", [])
	assert_true(skills.size() >= 4)

	var ids: Array[String] = []
	for e in skills:
		ids.append(String(e.get("id", "")))

	assert_true(ids.has("act_demo_single"))
	assert_true(ids.has("act_demo_cross"))
	assert_true(ids.has("pas_demo_turn_start_buff"))
	assert_true(ids.has("aur_demo_front_row_atk"))


func test_skill_db_loads_index_and_get_skill_lazy() -> void:
	var db := SkillDB.new()
	var r := db.reload_index()
	assert_true(bool(r.get("ok", false)))

	var sr := db.get_skill("act_demo_single", true)
	assert_true(bool(sr.get("ok", false)))
	var skill: Dictionary = sr.get("skill", {})
	assert_eq(String(skill.get("id", "")), "act_demo_single")
	assert_eq(String(skill.get("type", "")), "active")
	assert_true(typeof(skill.get("on_cast")) == TYPE_ARRAY)
	assert_true(typeof(skill.get("on_hit")) == TYPE_ARRAY)

