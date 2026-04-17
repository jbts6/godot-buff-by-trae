extends RefCounted
class_name IndexBuilder

const JsonIO := preload("res://addons/turn_skill_system/runtime/json_io.gd")
const SkillValidator := preload("res://addons/turn_skill_system/runtime/skill_validator.gd")

const SKILL_ROOT := "res://addons/turn_skill_system/data/skills"
const INDEX_PATH := "res://addons/turn_skill_system/data/skills/index.json"

static func rebuild_index() -> Dictionary:
	var issues: Array[Dictionary] = []
	var skills: Array[Dictionary] = []

	var type_dirs := {
		"active": SKILL_ROOT + "/active",
		"passive": SKILL_ROOT + "/passive",
		"aura": SKILL_ROOT + "/aura",
	}

	for t in type_dirs.keys():
		var dir_path := String(type_dirs[t])
		var da := DirAccess.open(dir_path)
		if da == null:
			continue
		da.list_dir_begin()
		while true:
			var fn := da.get_next()
			if fn == "":
				break
			if da.current_is_dir():
				continue
			if not fn.ends_with(".json"):
				continue
			var path := dir_path + "/" + fn
			var r := JsonIO.read_json(path)
			if not bool(r.get("ok", false)):
				issues.append({"severity":"error","file_path":path,"field_path":"$","message":"index_read_failed"})
				continue
			if typeof(r.get("data")) != TYPE_DICTIONARY:
				issues.append({"severity":"error","file_path":path,"field_path":"$","message":"skill_json_must_be_object"})
				continue
			var skill: Dictionary = r.get("data", {})
			var v_issues := SkillValidator.validate_skill(skill, path, false)
			issues.append_array(v_issues)

			var entry := {
				"id": String(skill.get("id", "")),
				"type": String(skill.get("type", t)),
				"path": path,
				"name": String(skill.get("name", "")),
				"tags": skill.get("tags", []),
				"mtime_unix": FileAccess.get_modified_time(path),
			}
			if entry.id == "":
				continue
			skills.append(entry)
		da.list_dir_end()

	var index := {
		"version": 1,
		"generated_at_unix": Time.get_unix_time_from_system(),
		"skills": skills,
	}

	return {"ok": true, "index": index, "issues": issues}


static func write_index(index: Dictionary) -> Dictionary:
	var preferred := ["version", "generated_at_unix", "skills"]
	return JsonIO.write_json_stable(INDEX_PATH, index, preferred)
