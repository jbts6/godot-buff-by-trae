extends RefCounted
class_name ApplyBuffEffect

const EventNames := preload("res://addons/turn_skill_system/runtime/event_names.gd")

func apply(effect: Dictionary, ctx: Dictionary, simulation: bool) -> Dictionary:
	var params: Dictionary = effect.get("params", {})
	var buff_id := String(params.get("buff_id", ""))
	if buff_id == "":
		return {"ok": false, "error": "apply_buff_missing_buff_id"}

	var scope := String(params.get("scope", "target"))
	var caster = ctx.get("caster")
	var target = ctx.get("target") if scope == "target" else caster
	var source = caster
	var omnibuff = ctx.get("omnibuff")
	var event_bus = ctx.get("event_bus")

	if simulation:
		return {"ok": true, "kind": "apply_buff", "value": 0, "meta": omnibuff.simulate_apply_buff(target, buff_id, source)}

	var r: Dictionary = omnibuff.apply_buff(target, buff_id, source)
	if not bool(r.get("ok", false)):
		return {"ok": false, "error": r.get("error", "apply_buff_failed")}
	if event_bus != null:
		event_bus.emit_event(EventNames.BUFF_APPLIED, {
			"skill_id": ctx.get("skill_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"buff_id": buff_id,
		})
	return {"ok": true, "kind": "apply_buff", "value": 0, "meta": r}
