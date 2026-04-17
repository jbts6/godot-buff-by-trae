extends RefCounted
class_name ApplyBuffEffect

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

	if simulation:
		return {"ok": true, "kind": "apply_buff", "value": 0, "meta": omnibuff.simulate_apply_buff(target, buff_id, source)}

	var r: Dictionary = omnibuff.apply_buff(target, buff_id, source)
	if not bool(r.get("ok", false)):
		return {"ok": false, "error": r.get("error", "apply_buff_failed")}
	return {"ok": true, "kind": "apply_buff", "value": 0, "meta": r}
