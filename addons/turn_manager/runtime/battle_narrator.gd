extends RefCounted
class_name BattleNarrator

const Log = preload("res://addons/log/log.gd")

signal line_emitted(bbcode_line: String, meta: Dictionary)

const DETAIL_CONCISE := 0
const DETAIL_VERBOSE := 1

var detail_level: int = DETAIL_CONCISE

var _event_bus = null
var _grid = null
var _ds = null
var _skill_db = null
var _runtime_dict: Dictionary = {}
var _name_map: Dictionary = {} # eid -> display name

var _turn_index: int = 0
var _round_index: int = 0
var _actor_id: int = -1
var _current_skill_id: String = ""


func bind(event_bus, grid, dataset, skill_db, runtime_dict: Dictionary, name_map: Dictionary = {}, opts: Dictionary = {}) -> void:
	_event_bus = event_bus
	_grid = grid
	_ds = dataset
	_skill_db = skill_db
	_runtime_dict = runtime_dict
	_name_map = name_map
	detail_level = int(opts.get("detail_level", DETAIL_CONCISE))

	if _event_bus != null and _event_bus.has_signal("event_emitted"):
		if not _event_bus.event_emitted.is_connected(_on_event):
			_event_bus.event_emitted.connect(_on_event)


func set_detail_level(level: int) -> void:
	detail_level = clampi(int(level), DETAIL_CONCISE, DETAIL_VERBOSE)


func _on_event(event_name: String, data: Dictionary) -> void:
	match String(event_name):
		"battle_started":
			_emit_text("战斗开始！", {"event": "battle_started"})
		"buff_applied":
			_emit_buff_applied(data)
		"buff_removed":
			_emit_buff_removed(data)
		"turn_order_computed":
			_emit_turn_order(data)
		"turn_started":
			_turn_index = int(data.get("turn_index", _turn_index))
			_actor_id = int(data.get("actor_id", -1))
			_emit_text("回合 %d：%s 行动" % [_turn_index, _name_of(_actor_id)], {"event": "turn_started", "turn_index": _turn_index, "actor_id": _actor_id})
		"action_started":
			_turn_index = int(data.get("turn_index", _turn_index))
			_actor_id = int(data.get("actor_id", _actor_id))
			_current_skill_id = String(data.get("skill_id", ""))
			_emit_text("%s 使用【%s】" % [_name_of(_actor_id), _skill_name(_current_skill_id)], {"event": "action_started", "turn_index": _turn_index, "actor_id": _actor_id, "skill_id": _current_skill_id})
		"after_damage":
			_emit_damage_line(data)
		"after_heal":
			_emit_heal_line(data)
		"unit_died":
			var dead_id = int(data.get("actor_id", -1))
			_emit_text("%s 倒下了！" % [_name_of(dead_id)], {"event": "unit_died", "actor_id": dead_id})
		_:
			# 其它事件先不播报；后续会补充 buff_applied/buff_removed 等。
			pass


func _emit_buff_applied(data: Dictionary) -> void:
	var caster_id = int(data.get("caster_id", -1))
	var target_id = int(data.get("target_id", -1))
	var buff_id = String(data.get("buff_id", ""))
	var skill_id = String(data.get("skill_id", ""))
	var caster_name = _name_of(caster_id)
	var target_name = _name_of(target_id)
	var buff_name = _buff_name(buff_id)
	if caster_id >= 0 and target_id >= 0 and caster_id != target_id:
		var concise = "%s 使 %s 获得效果【%s】" % [caster_name, target_name, buff_name]
		var verbose = concise
		if skill_id != "":
			verbose += "（来源技能：%s）" % [_skill_name(skill_id)]
		_emit_text(concise, {
			"event": "buff_applied",
			"caster_id": caster_id,
			"target_id": target_id,
			"buff_id": buff_id,
			"skill_id": skill_id,
			"text_concise": concise,
			"text_verbose": verbose,
		})
	else:
		var concise2 = "%s 获得效果【%s】" % [target_name, buff_name]
		var verbose2 = concise2
		if skill_id != "":
			verbose2 += "（来源技能：%s）" % [_skill_name(skill_id)]
		_emit_text(concise2, {
			"event": "buff_applied",
			"caster_id": caster_id,
			"target_id": target_id,
			"buff_id": buff_id,
			"skill_id": skill_id,
			"text_concise": concise2,
			"text_verbose": verbose2,
		})


func _emit_buff_removed(data: Dictionary) -> void:
	var target_id = int(data.get("target_id", -1))
	var buff_id = String(data.get("buff_id", ""))
	_emit_text("%s 失去效果【%s】" % [_name_of(target_id), _buff_name(buff_id)], {"event": "buff_removed", "target_id": target_id, "buff_id": buff_id})


func _emit_turn_order(data: Dictionary) -> void:
	var round_idx = int(data.get("round_index", _round_index))
	if round_idx != _round_index and round_idx > 0:
		_round_index = round_idx
		_emit_text("第 %d 轮开始" % [_round_index], {"event": "round_started", "round_index": _round_index})

	var order_any: Variant = data.get("order", [])
	if typeof(order_any) != TYPE_ARRAY:
		return
	var order: Array = order_any
	if order.is_empty():
		return
	var parts: Array[String] = []
	for it_any in order:
		if typeof(it_any) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_any
		var eid = int(it.get("eid", -1))
		var spd = float(it.get("speed", 0.0))
		parts.append("%s(%.0f)" % [_name_of(eid), spd])
	if parts.is_empty():
		return
	_emit_text("计算出手顺序：" + " > ".join(parts), {"event": "turn_order_computed"})


func _emit_damage_line(data: Dictionary) -> void:
	var caster_id = int(data.get("caster_id", -1))
	var target_id = int(data.get("target_id", -1))
	var final_damage = float(data.get("final_damage", 0.0))
	var skill_id = String(data.get("skill_id", _current_skill_id))

	# 简洁模式：每条 AFTER_DAMAGE 直接输出一行（AOE 会自然出现多行）
	var hp_pair = _get_hp_pair(target_id)
	var concise = "%s 受到 %.0f 伤害，HP %.0f/%.0f" % [
		_name_of(target_id),
		final_damage,
		hp_pair.x,
		hp_pair.y,
	]
	var verbose = concise + "（来自：%s｜技能：%s）" % [_name_of(caster_id), _skill_name(skill_id)]
	_emit_text(concise, {
		"event": "after_damage",
		"turn_index": _turn_index,
		"skill_id": skill_id,
		"caster_id": caster_id,
		"target_id": target_id,
		"final_damage": final_damage,
		"text_concise": concise,
		"text_verbose": verbose,
	})


func _emit_heal_line(data: Dictionary) -> void:
	var caster_id = int(data.get("caster_id", -1))
	var target_id = int(data.get("target_id", -1))
	var amount = float(data.get("amount", 0.0))
	var skill_id = String(data.get("skill_id", _current_skill_id))

	var hp_pair = _get_hp_pair(target_id)
	var concise = "%s 恢复 %.0f，HP %.0f/%.0f" % [
		_name_of(target_id),
		amount,
		hp_pair.x,
		hp_pair.y,
	]
	var verbose = concise + "（施法者：%s｜技能：%s）" % [_name_of(caster_id), _skill_name(skill_id)]
	_emit_text(concise, {
		"event": "after_heal",
		"turn_index": _turn_index,
		"skill_id": skill_id,
		"caster_id": caster_id,
		"target_id": target_id,
		"amount": amount,
		"text_concise": concise,
		"text_verbose": verbose,
	})


func _emit_text(text: String, meta: Dictionary = {}) -> void:
	# 产出 BBCode（log.gd 颜色风格），用于 RichTextLabel
	var m: Dictionary = meta.duplicate(true)
	if not m.has("text_concise"):
		m["text_concise"] = text
	if not m.has("text_verbose"):
		m["text_verbose"] = text
	var chosen = String(m.get("text_verbose")) if detail_level == DETAIL_VERBOSE else String(m.get("text_concise"))
	var bb = Log.to_printable([chosen], {"pretty": true})
	line_emitted.emit(bb, m)


func _name_of(eid: int) -> String:
	if eid < 0:
		return "?"
	var n_any: Variant = _name_map.get(eid, null)
	if n_any != null and String(n_any) != "":
		return String(n_any)
	return "E%d" % eid


func _skill_name(skill_id: String) -> String:
	if skill_id == "":
		return "?"
	if _skill_db != null and _skill_db.has_method("get_skill"):
		var r: Dictionary = _skill_db.call("get_skill", skill_id, true)
		if bool(r.get("ok", false)):
			var skill: Dictionary = r.get("skill", {})
			var n = String(skill.get("name", ""))
			if n != "":
				return n
	return skill_id


func _buff_name(buff_id: String) -> String:
	if buff_id == "":
		return "?"
	# 若 dataset 可反查 buff.name，则优先用 name；否则退化 buff_id
	if _ds != null and "buff_defs" in _ds:
		var defs_any: Variant = _ds.get("buff_defs")
		if typeof(defs_any) == TYPE_ARRAY:
			var defs: Array = defs_any
			for d_any in defs:
				if typeof(d_any) != TYPE_DICTIONARY:
					continue
				var d: Dictionary = d_any
				if String(d.get("id", "")) == buff_id:
					var n = String(d.get("name", ""))
					if n != "":
						return n
					break
	return buff_id


func _get_hp_pair(entity_id: int) -> Vector2:
	var hp_id = _stat_id("HP")
	var max_hp_id = _stat_id("MAX_HP")
	var stats = _get_stats(entity_id)
	if stats == null:
		return Vector2(0.0, 0.0)
	var hp = float(stats.get_final(hp_id)) if hp_id >= 0 else 0.0
	var max_hp = float(stats.get_final(max_hp_id)) if max_hp_id >= 0 else 0.0
	return Vector2(hp, max_hp)


func _stat_id(name: String) -> int:
	if _ds == null:
		return -1
	if not _ds.has_method("stat_id"):
		return -1
	return int(_ds.call("stat_id", name))


func _get_stats(entity_id: int):
	var stats_by_entity: Dictionary = _runtime_dict.get("stats_by_entity", {})
	return stats_by_entity.get(entity_id, null)
