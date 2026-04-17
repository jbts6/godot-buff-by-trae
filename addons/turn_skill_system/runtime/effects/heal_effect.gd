extends RefCounted
class_name HealEffect

const Formula := preload("res://addons/turn_skill_system/runtime/formula.gd")
const EventNames := preload("res://addons/turn_skill_system/runtime/event_names.gd")

func apply(effect: Dictionary, ctx: Dictionary, simulation: bool) -> Dictionary:
	var params: Dictionary = effect.get("params", {})
	var rounding := String(params.get("rounding", "floor"))

	var amount := 0.0
	if params.has("amount"):
		amount = float(params.get("amount"))
	elif params.has("amount_expr"):
		var r := Formula.eval_expr(String(params.get("amount_expr")), ctx, rounding)
		if not bool(r.get("ok", false)):
			return {"ok": false, "error": r.get("error", "formula_failed"), "resolved_formulas": [r.get("resolved", {})]}
		amount = float(r.get("value", 0))
	else:
		return {"ok": false, "error": "heal_missing_amount"}

	var caster = ctx.get("caster")
	var target = ctx.get("target")
	var event_bus = ctx.get("event_bus")

	if event_bus != null:
		event_bus.emit_event(EventNames.BEFORE_HEAL, {
			"skill_id": ctx.get("skill_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"amount": amount,
		})

	if simulation:
		return {"ok": true, "kind": "heal", "value": amount, "predicted": true, "meta": {"amount": amount}}

	var final_amount = amount
	var meta = {"amount": amount}

	var omnibuff = ctx.get("omnibuff")
	if omnibuff != null and omnibuff.has_method("heal"):
		var hr: Dictionary = omnibuff.heal(caster, target, amount, ctx)
		if hr.get("ok", false):
			final_amount = float(hr.get("final_heal", amount))
			meta = hr.get("meta", {})
		else:
			return {"ok": false, "error": hr.get("error", "omnibuff_heal_failed")}

	if event_bus != null:
		event_bus.emit_event(EventNames.AFTER_HEAL, {
			"skill_id": ctx.get("skill_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"amount": final_amount,
		})

	return {"ok": true, "kind": "heal", "value": final_amount, "meta": meta}
