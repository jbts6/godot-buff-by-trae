extends RefCounted
class_name DamageEffect

const Formula := preload("res://addons/turn_skill_system/runtime/formula.gd")
const EventNames := preload("res://addons/turn_skill_system/runtime/event_names.gd")

func apply(effect: Dictionary, ctx: Dictionary, simulation: bool) -> Dictionary:
	var params: Dictionary = effect.get("params", {})
	var rounding := String(params.get("rounding", "floor"))

	var base_damage := 0.0
	if params.has("amount"):
		base_damage = float(params.get("amount"))
	elif params.has("amount_expr"):
		var r := Formula.eval_expr(String(params.get("amount_expr")), ctx, rounding)
		if not bool(r.get("ok", false)):
			return {"ok": false, "error": r.get("error", "formula_failed"), "resolved_formulas": [r.get("resolved", {})]}
		base_damage = float(r.get("value", 0))
	else:
		return {"ok": false, "error": "damage_missing_amount"}

	var caster = ctx.get("caster")
	var target = ctx.get("target")
	var event_bus = ctx.get("event_bus")

	# 事件：before_damage
	if event_bus != null:
		event_bus.emit_event(EventNames.BEFORE_DAMAGE, {
			"skill_id": ctx.get("skill_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"base_damage": base_damage,
		})

	if simulation:
		return {
			"ok": true,
			"kind": "damage",
			"value": base_damage,
			"predicted": true,
			"meta": {"base_damage": base_damage},
		}

	var omnibuff = ctx.get("omnibuff")
	var dr: Dictionary = omnibuff.deal_damage(caster, target, base_damage, ctx)
	if not bool(dr.get("ok", false)):
		return {"ok": false, "error": dr.get("error", "deal_damage_failed")}

	# 事件：after_damage
	if event_bus != null:
		event_bus.emit_event(EventNames.AFTER_DAMAGE, {
			"skill_id": ctx.get("skill_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"final_damage": dr.get("final_damage", 0),
		})

	return {"ok": true, "kind": "damage", "value": dr.get("final_damage", 0), "meta": dr.get("meta", {})}
