extends RefCounted
class_name PassiveManager

## 被动技能管理器（最小闭环）：
## - register_unit_passives(unit, [skill_id...])
## - bind(event_bus, db, effects, omnibuff, grid)
## - 监听 event_bus.event_emitted，根据 triggers 执行 effects（目前仅支持 chance 与无条件）

var _event_bus = null
var _db = null
var _effects = null
var _omnibuff = null
var _grid = null

var _passives_by_owner: Dictionary = {} # owner_id -> Array[Dictionary] (skill dict)

func bind(event_bus, db, effects, omnibuff, grid) -> void:
	_event_bus = event_bus
	_db = db
	_effects = effects
	_omnibuff = omnibuff
	_grid = grid
	if _event_bus != null and not _event_bus.event_emitted.is_connected(_on_event_emitted):
		_event_bus.event_emitted.connect(_on_event_emitted)


func register_unit_passives(owner_unit, passive_skill_ids: Array[String]) -> void:
	var owner_id := int(owner_unit.entity_id)
	var arr: Array = []
	for sid in passive_skill_ids:
		var r: Dictionary = _db.get_skill(String(sid), true)
		if not bool(r.get("ok", false)):
			continue
		var skill: Dictionary = r.get("skill", {})
		if String(skill.get("type", "")) != "passive":
			continue
		arr.append(skill)
	_passives_by_owner[owner_id] = arr


func _on_event_emitted(event_type: String, data: Dictionary) -> void:
	if _db == null or _effects == null:
		return
	for owner_id in _passives_by_owner.keys():
		var owner_unit = _find_unit_by_id(owner_id)
		if owner_unit == null:
			continue
		var skills: Array = _passives_by_owner[owner_id]
		for skill in skills:
			for trig in skill.get("triggers", []):
				if typeof(trig) != TYPE_DICTIONARY:
					continue
				if String(trig.get("event", "")) != event_type:
					continue
				var chance := float(trig.get("chance", 1.0))
				if chance < 1.0:
					# 最小实现：不做可回放 rng；后续可用 rng_seed + roll_key
					if randf() > chance:
						continue
				var effects_arr: Array = trig.get("effects", [])
				for e in effects_arr:
					var ctx := {
						"skill_id": String(skill.get("id", "")),
						"skill": skill,
						"caster": owner_unit,
						"target": owner_unit,
						"grid": _grid,
						"event_bus": _event_bus,
						"omnibuff": _omnibuff,
						"turn_index": int(data.get("turn_index", 0)),
						"roll_key": int(data.get("roll_key", 0)),
						"rng_seed": int(data.get("rng_seed", 0)),
						"damage_type": 0,
						"element": 0,
						"tags": skill.get("tags", []),
						"tags_mask": int(data.get("tags_mask", 0)),
						"skill_id_int": int(data.get("skill_id_int", -1)),
						"a_stats": {},
						"t_stats": {},
					}
					_effects.apply_effect(e, ctx, false)


func _find_unit_by_id(entity_id: int):
	if _grid == null:
		return null
	for u in _grid._units:
		if u != null and int(u.entity_id) == entity_id:
			return u
	return null
