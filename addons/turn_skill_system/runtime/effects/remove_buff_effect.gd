extends RefCounted
class_name RemoveBuffEffect

const EventNames := preload("res://addons/turn_skill_system/runtime/event_names.gd")

func apply(effect: Dictionary, ctx: Dictionary, simulation: bool) -> Dictionary:
	var params: Dictionary = effect.get("params", {})
	var buff_id := String(params.get("buff_id", ""))
	if buff_id == "":
		return {"ok": false, "error": "remove_buff_missing_buff_id"}

	var scope := String(params.get("scope", "target"))
	var caster = ctx.get("caster")
	var target = ctx.get("target") if scope == "target" else caster
	var source = caster
	var remove_scope := String(params.get("remove_scope", "ALL"))
	var omnibuff = ctx.get("omnibuff")
	var event_bus = ctx.get("event_bus")

	if simulation:
		return {"ok": true, "kind": "remove_buff", "value": 0, "meta": omnibuff.simulate_remove_buff(target, buff_id, source, remove_scope)}

	var r: Dictionary = omnibuff.remove_buff(target, buff_id, source, remove_scope)
	if not bool(r.get("ok", false)):
		return {"ok": false, "error": r.get("error", "remove_buff_failed")}
	if event_bus != null:
		event_bus.emit_event(EventNames.BUFF_REMOVED, {
			"skill_id": ctx.get("skill_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"buff_id": buff_id,
			"remove_scope": remove_scope,
		})
	return {"ok": true, "kind": "remove_buff", "value": 0, "meta": r}
