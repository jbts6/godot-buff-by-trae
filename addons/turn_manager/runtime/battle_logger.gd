extends RefCounted
class_name BattleLogger

const Log = preload("res://addons/log/log.gd")


func log_banner(title: String) -> void:
	Log.pr("=== ", title, " ===")


func log_event(event_name: String, data: Dictionary) -> void:
	# data 往往比较长，用 prn 更清晰
	Log.prn("[Event]", event_name, data)


func log_turn_started(actor: Node, turn_index: int) -> void:
	var eid = int(actor.get("entity_id"))
	var camp = String(actor.get("camp"))
	Log.pr("[TurnStart]", {"turn_index": turn_index, "entity_id": eid, "camp": camp})


func log_turn_ended(actor: Node, turn_index: int) -> void:
	var eid = int(actor.get("entity_id"))
	Log.pr("[TurnEnd]", {"turn_index": turn_index, "entity_id": eid})


func log_boss_cooldowns(tag: String, cooldowns: Dictionary) -> void:
	Log.pr("[BossCooldowns]", tag, cooldowns)


func log_units_status(tag: String, units: Array, stat_ids: Dictionary) -> void:
	var rows: Array = []
	for u in units:
		if u == null:
			continue
		rows.append(_make_unit_status_row(u, stat_ids))
	Log.prn("[Status]", tag, rows)


func _make_unit_status_row(u: Node, stat_ids: Dictionary) -> Dictionary:
	var st = u.get("stats")
	var dead = (u.has_method("is_dead") and bool(u.call("is_dead")))

	return {
		"eid": int(u.get("entity_id")),
		"camp": String(u.get("camp")),
		"dead": dead,
		"hp": _get_stat_value(st, int(stat_ids.get("HP", -1))),
		"max_hp": _get_stat_value(st, int(stat_ids.get("MAX_HP", -1))),
		"mp": _get_stat_value(st, int(stat_ids.get("MP", -1))),
		"max_mp": _get_stat_value(st, int(stat_ids.get("MAX_MP", -1))),
		"speed": _get_stat_value(st, int(stat_ids.get("SPEED", -1))),
		"cell": Vector2i(u.get("cell")),
	}


func _get_stat_value(stats, stat_id: int) -> float:
	if stats == null:
		return 0.0
	if stat_id < 0:
		return 0.0
	if not stats.has_method("get_final"):
		return 0.0
	return float(stats.get_final(stat_id))
