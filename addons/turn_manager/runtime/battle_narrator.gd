extends RefCounted
class_name BattleNarrator

const Log = preload("res://addons/log/log.gd")

signal line_emitted(bbcode_line: String, meta: Dictionary)

const DETAIL_CONCISE := 0
const DETAIL_VERBOSE := 1

var detail_level: int = DETAIL_CONCISE

# 主题（classic：友方绿 / 敌方红）
const COLOR_ALLY := "#43AA8B"
const COLOR_ENEMY := "#F94144"
const COLOR_SKILL := "#90DBF4"
const COLOR_TURN := "#F9C74F"
const COLOR_ROUND := "#F9C74F"
const COLOR_MUTED := "#7C8498"
const COLOR_LINE := "#666666"

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
			_emit_bb(_bb_text("战斗开始！"), {"event": "battle_started"})
		"item_used":
			_emit_item_used(data)
		"buff_applied":
			_emit_buff_applied(data)
		"buff_removed":
			_emit_buff_removed(data)
		"turn_order_computed":
			_emit_turn_order(data)
		"turn_started":
			_turn_index = int(data.get("turn_index", _turn_index))
			_actor_id = int(data.get("actor_id", -1))
			_emit_bb(_bb_sep_soft(), {"event": "turn_sep", "turn_index": _turn_index})
			_emit_bb(
				"%s：%s 行动" % [
					_bb_turn(_turn_index),
					_bb_unit(_actor_id),
				],
				{"event": "turn_started", "turn_index": _turn_index, "actor_id": _actor_id}
			)
		"action_started":
			# item 会由 item_used 事件播报，避免重复
			if String(data.get("kind", "skill")) == "item" or String(data.get("item_id", "")) != "":
				return
			_turn_index = int(data.get("turn_index", _turn_index))
			_actor_id = int(data.get("actor_id", _actor_id))
			_current_skill_id = String(data.get("skill_id", ""))
			_emit_bb(
				"%s 使用 %s" % [
					_bb_unit(_actor_id),
					_bb_skill(_current_skill_id),
				],
				{"event": "action_started", "turn_index": _turn_index, "actor_id": _actor_id, "skill_id": _current_skill_id}
			)
		"after_damage":
			_emit_damage_line(data)
		"after_heal":
			_emit_heal_line(data)
		"unit_died":
			var dead_id = int(data.get("actor_id", -1))
			_emit_bb("%s 倒下了！" % [_bb_unit(dead_id)], {"event": "unit_died", "actor_id": dead_id})
		_:
			# 其它事件先不播报；后续会补充 buff_applied/buff_removed 等。
			pass


func _emit_item_used(data: Dictionary) -> void:
	var actor_id = int(data.get("actor_id", -1))
	var item_id = String(data.get("item_id", ""))
	var item_name = String(data.get("item_name", ""))
	var target_id = int(data.get("target_id", -1))

	var item_disp = item_name if item_name != "" else item_id
	var s = "%s 使用 道具%s" % [
		_bb_unit(actor_id),
		_bb_item(item_disp),
	]
	if target_id >= 0:
		s += _bb_muted("（目标：%s）" % [_name_of(target_id)])
	_emit_bb(s, {
		"event": "item_used",
		"actor_id": actor_id,
		"item_id": item_id,
		"target_id": target_id,
	})


func _emit_buff_applied(data: Dictionary) -> void:
	var caster_id = int(data.get("caster_id", -1))
	var target_id = int(data.get("target_id", -1))
	var buff_id = String(data.get("buff_id", ""))
	var skill_id = String(data.get("skill_id", ""))
	var caster_name = _name_of(caster_id)
	var target_name = _name_of(target_id)
	var buff_name = _buff_name(buff_id)
	if caster_id >= 0 and target_id >= 0 and caster_id != target_id:
		var concise = "%s 使 %s 获得效果 %s" % [_bb_unit(caster_id), _bb_unit(target_id), _bb_buff(buff_id)]
		var verbose = concise
		if skill_id != "":
			verbose += _bb_muted("（来源技能：%s）" % [_skill_name(skill_id)])
		_emit_bb(concise, {
			"event": "buff_applied",
			"caster_id": caster_id,
			"target_id": target_id,
			"buff_id": buff_id,
			"skill_id": skill_id,
			"text_concise": concise,
			"text_verbose": verbose,
		})
	else:
		var concise2 = "%s 获得效果 %s" % [_bb_unit(target_id), _bb_buff(buff_id)]
		var verbose2 = concise2
		if skill_id != "":
			verbose2 += _bb_muted("（来源技能：%s）" % [_skill_name(skill_id)])
		_emit_bb(concise2, {
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
	_emit_bb("%s 失去效果 %s" % [_bb_unit(target_id), _bb_buff(buff_id)], {"event": "buff_removed", "target_id": target_id, "buff_id": buff_id})


func _emit_turn_order(data: Dictionary) -> void:
	var round_idx = int(data.get("round_index", _round_index))
	if round_idx != _round_index and round_idx > 0:
		_round_index = round_idx
		_emit_bb(_bb_sep_hard(), {"event": "round_sep", "round_index": _round_index})
		_emit_bb(_bb_round(_round_index), {"event": "round_started", "round_index": _round_index})

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
		parts.append("%s%s" % [_bb_unit(eid), _bb_muted("(%.0f)" % spd)])
	if parts.is_empty():
		return
	_emit_bb(_bb_muted("计算出手顺序：") + " > ".join(parts), {"event": "turn_order_computed"})


func _emit_damage_line(data: Dictionary) -> void:
	var caster_id = int(data.get("caster_id", -1))
	var target_id = int(data.get("target_id", -1))
	var final_damage = float(data.get("final_damage", 0.0))
	var skill_id = String(data.get("skill_id", _current_skill_id))

	# 简洁模式：每条 AFTER_DAMAGE 直接输出一行（AOE 会自然出现多行）
	var hp_pair = _get_hp_pair(target_id)
	var concise = "- %s 受到 %s 伤害，%s" % [
		_bb_unit(target_id),
		_bb_dmg(final_damage),
		_bb_hp(hp_pair.x, hp_pair.y),
	]
	var verbose = concise + _bb_muted("（来自：%s｜技能：%s）" % [_name_of(caster_id), _skill_name(skill_id)])
	_emit_bb(concise, {
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
	var concise = "- %s 恢复 %s，%s" % [
		_bb_unit(target_id),
		_bb_heal(amount),
		_bb_hp(hp_pair.x, hp_pair.y),
	]
	var verbose = concise + _bb_muted("（施法者：%s｜技能：%s）" % [_name_of(caster_id), _skill_name(skill_id)])
	_emit_bb(concise, {
		"event": "after_heal",
		"turn_index": _turn_index,
		"skill_id": skill_id,
		"caster_id": caster_id,
		"target_id": target_id,
		"amount": amount,
		"text_concise": concise,
		"text_verbose": verbose,
	})

func _emit_bb(bbcode: String, meta: Dictionary = {}) -> void:
	var m: Dictionary = meta.duplicate(true)
	# 兼容 BattleLogPanel 的重渲染：同时提供 concise/verbose 的 BBCode 版本
	if not m.has("bb_concise"):
		m["bb_concise"] = bbcode
	if not m.has("bb_verbose"):
		m["bb_verbose"] = bbcode
	line_emitted.emit(bbcode, m)


func _bb_text(s: String) -> String:
	# 普通文本走 log.gd 的 pretty（顺便兼容控制台输出）
	return Log.to_printable([s], {"pretty": true})


func _bb_color(s: String, color_hex: String, bold: bool = false) -> String:
	if bold:
		return "[color=%s][b]%s[/b][/color]" % [color_hex, s]
	return "[color=%s]%s[/color]" % [color_hex, s]


func _bb_muted(s: String) -> String:
	return _bb_color(s, COLOR_MUTED, false)


func _bb_turn(turn_index: int) -> String:
	return _bb_color("回合 %d" % turn_index, COLOR_TURN, true)


func _bb_round(round_index: int) -> String:
	return _bb_color("第 %d 轮开始" % round_index, COLOR_ROUND, true)


func _bb_skill(skill_id: String) -> String:
	return _bb_color("【%s】" % _skill_name(skill_id), COLOR_SKILL, true)

func _bb_item(item_name: String) -> String:
	return _bb_color("【%s】" % item_name, COLOR_SKILL, true)


func _bb_buff(buff_id: String) -> String:
	return _bb_color("【%s】" % _buff_name(buff_id), COLOR_SKILL, true)


func _bb_dmg(v: float) -> String:
	return _bb_color("%.0f" % v, COLOR_ENEMY, true)


func _bb_heal(v: float) -> String:
	return _bb_color("%.0f" % v, COLOR_ALLY, true)


func _bb_hp(hp: float, max_hp: float) -> String:
	return _bb_muted("HP %.0f/%.0f" % [hp, max_hp])


func _bb_sep_hard() -> String:
	return _bb_color("────────────────────────", COLOR_LINE, false)


func _bb_sep_soft() -> String:
	return _bb_color("------------------------", COLOR_LINE, false)


func _bb_unit(eid: int) -> String:
	var camp = _camp_of(eid)
	var n = _name_of(eid)
	if camp == "ally":
		return _bb_color(n, COLOR_ALLY, true)
	if camp == "enemy":
		return _bb_color(n, COLOR_ENEMY, true)
	return _bb_color(n, COLOR_MUTED, false)


func _camp_of(eid: int) -> String:
	if _grid == null:
		return ""
	if not ("_units" in _grid):
		return ""
	var units_any: Variant = _grid.get("_units")
	if typeof(units_any) != TYPE_ARRAY:
		return ""
	var units: Array = units_any
	for u in units:
		if u == null:
			continue
		if int(u.get("entity_id")) == eid:
			return String(u.get("camp"))
	return ""


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
	if _ds != null and _ds.has_method("buff_id"):
		var bdid = int(_ds.buff_id(buff_id))
		if bdid >= 0:
			var defs_any: Variant = _ds.get("buff_defs")
			if typeof(defs_any) == TYPE_ARRAY and bdid < defs_any.size():
				var d_any = defs_any[bdid]
				if typeof(d_any) == TYPE_DICTIONARY:
					var n = String(d_any.get("name", ""))
					if n != "":
						return n
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
