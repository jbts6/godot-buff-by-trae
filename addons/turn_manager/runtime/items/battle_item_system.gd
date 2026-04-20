extends RefCounted
class_name BattleItemSystem

## 战斗内道具执行系统（独立背包/道具系统的“战斗适配层”）
##
## 目标：
## - 校验与消耗 inventory
## - 解析 item_db 的 effects 并执行（调用 omnibuff_adapter）
## - 发出 BattleEventBus 事件（用于 BattleNarrator 播报）

const EventNames := preload("res://addons/turn_skill_system/runtime/event_names.gd")

signal item_executed(result: Dictionary)

class UnitStub extends Node:
	var entity_id: int = -1
	var camp: String = ""
	var cell: Vector2i = Vector2i.ZERO


var _event_bus = null
var _omnibuff_adapter = null
var _inventory = null
var _ds = null
var _runtime_dict: Dictionary = {}
var _item_db: Dictionary = {}
var _grid = null # optional; if provided, used for cell->unit resolution


func bind(event_bus, omnibuff_adapter, inventory, dataset, runtime_dict: Dictionary, item_db: Dictionary, grid = null) -> void:
	_event_bus = event_bus
	_omnibuff_adapter = omnibuff_adapter
	_inventory = inventory
	_ds = dataset
	_runtime_dict = runtime_dict
	_item_db = item_db
	_grid = grid


func execute_item(actor_id: int, item_id: String, target_cell: Vector2i) -> Dictionary:
	if _event_bus == null:
		return {"ok": false, "error": "missing_event_bus"}
	if _inventory == null:
		return {"ok": false, "error": "missing_inventory"}
	if not _item_db.has(item_id):
		return {"ok": false, "error": "unknown_item"}

	var item_any: Variant = _item_db.get(item_id)
	if typeof(item_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid_item_def"}
	var item: Dictionary = item_any

	# 1) consume
	if _inventory.has_method("consume"):
		var cr: Dictionary = _inventory.call("consume", item_id, 1)
		if not bool(cr.get("ok", false)):
			return {"ok": false, "error": cr.get("error", "consume_failed")}
	else:
		return {"ok": false, "error": "inventory_missing_consume"}

	var actor = _get_unit_by_id(actor_id)
	var target = _get_unit_by_cell_or_fallback(target_cell, actor)
	var target_id = int(target.entity_id)

	# 2) announce
	_event_bus.emit_event("item_used", {
		"actor_id": actor_id,
		"item_id": item_id,
		"item_name": String(item.get("name", "")),
		"target_id": target_id,
		"target_cell": target_cell,
	})

	# 3) execute effects
	var effects_any: Variant = item.get("effects", [])
	var effects: Array = effects_any if typeof(effects_any) == TYPE_ARRAY else []
	var errors: Array[String] = []

	var ctx := {
		"item_id": item_id,
		"item": item,
		"skill_id": "", # 与 skill 系统区分
		"caster": actor,
		"target": target,
		"grid": _grid,
		"event_bus": _event_bus,
		"omnibuff": _omnibuff_adapter,
		"dataset": _ds,
		"runtime_dict": _runtime_dict,
	}

	for e_any in effects:
		if typeof(e_any) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_any
		var kind = String(e.get("kind", ""))
		if kind == "heal":
			var hr = _apply_heal(e, ctx)
			if not bool(hr.get("ok", false)):
				errors.append(String(hr.get("error", "heal_failed")))
		elif kind == "damage":
			var dr = _apply_damage(e, ctx)
			if not bool(dr.get("ok", false)):
				errors.append(String(dr.get("error", "damage_failed")))
		elif kind == "apply_buff":
			var ar = _apply_buff(e, ctx)
			if not bool(ar.get("ok", false)):
				errors.append(String(ar.get("error", "apply_buff_failed")))
		elif kind == "remove_buff":
			var rr = _remove_buff(e, ctx)
			if not bool(rr.get("ok", false)):
				errors.append(String(rr.get("error", "remove_buff_failed")))
		else:
			errors.append("unknown_effect_kind:%s" % kind)

	var ok = errors.is_empty()
	var res := {"ok": ok, "errors": errors}
	item_executed.emit(res)
	return res


func _apply_heal(effect: Dictionary, ctx: Dictionary) -> Dictionary:
	var params: Dictionary = effect.get("params", {})
	var amount = float(params.get("amount", 0.0))
	var caster = ctx.get("caster")
	var target = ctx.get("target")
	if amount <= 0.0:
		return {"ok": false, "error": "heal_amount_invalid"}

	if _event_bus != null:
		_event_bus.emit_event(EventNames.BEFORE_HEAL, {
			"skill_id": "",
			"item_id": ctx.get("item_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"amount": amount,
		})

	var final_amount = amount
	if _omnibuff_adapter != null and _omnibuff_adapter.has_method("heal"):
		var hr: Dictionary = _omnibuff_adapter.call("heal", caster, target, amount, ctx)
		if bool(hr.get("ok", false)):
			final_amount = float(hr.get("final_heal", amount))
		else:
			return {"ok": false, "error": hr.get("error", "omnibuff_heal_failed")}

	if _event_bus != null:
		_event_bus.emit_event(EventNames.AFTER_HEAL, {
			"skill_id": "",
			"item_id": ctx.get("item_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"amount": final_amount,
		})
	return {"ok": true, "final_heal": final_amount}


func _apply_damage(effect: Dictionary, ctx: Dictionary) -> Dictionary:
	var params: Dictionary = effect.get("params", {})
	var base_damage = float(params.get("amount", 0.0))
	var caster = ctx.get("caster")
	var target = ctx.get("target")
	if base_damage <= 0.0:
		return {"ok": false, "error": "damage_amount_invalid"}

	if _event_bus != null:
		_event_bus.emit_event(EventNames.BEFORE_DAMAGE, {
			"skill_id": "",
			"item_id": ctx.get("item_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"base_damage": base_damage,
		})

	var final_damage = base_damage
	if _omnibuff_adapter != null and _omnibuff_adapter.has_method("deal_damage"):
		var dr: Dictionary = _omnibuff_adapter.call("deal_damage", caster, target, base_damage, ctx)
		if bool(dr.get("ok", false)):
			final_damage = float(dr.get("final_damage", base_damage))
		else:
			return {"ok": false, "error": dr.get("error", "omnibuff_damage_failed")}

	if _event_bus != null:
		_event_bus.emit_event(EventNames.AFTER_DAMAGE, {
			"skill_id": "",
			"item_id": ctx.get("item_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"final_damage": final_damage,
		})
	return {"ok": true, "final_damage": final_damage}


func _apply_buff(effect: Dictionary, ctx: Dictionary) -> Dictionary:
	var params: Dictionary = effect.get("params", {})
	var buff_id = String(params.get("buff_id", ""))
	if buff_id == "":
		return {"ok": false, "error": "apply_buff_missing_buff_id"}
	var caster = ctx.get("caster")
	var target = ctx.get("target")
	if _omnibuff_adapter == null or not _omnibuff_adapter.has_method("apply_buff"):
		return {"ok": false, "error": "missing_apply_buff"}
	var r: Dictionary = _omnibuff_adapter.call("apply_buff", target, buff_id, caster)
	if not bool(r.get("ok", false)):
		return {"ok": false, "error": r.get("error", "apply_buff_failed")}
	if _event_bus != null:
		_event_bus.emit_event(EventNames.BUFF_APPLIED, {
			"skill_id": "",
			"item_id": ctx.get("item_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"buff_id": buff_id,
		})
	return {"ok": true}


func _remove_buff(effect: Dictionary, ctx: Dictionary) -> Dictionary:
	var params: Dictionary = effect.get("params", {})
	var buff_id = String(params.get("buff_id", ""))
	if buff_id == "":
		return {"ok": false, "error": "remove_buff_missing_buff_id"}
	var remove_scope = String(params.get("remove_scope", "ALL"))
	var caster = ctx.get("caster")
	var target = ctx.get("target")
	if _omnibuff_adapter == null or not _omnibuff_adapter.has_method("remove_buff"):
		return {"ok": false, "error": "missing_remove_buff"}
	var r: Dictionary = _omnibuff_adapter.call("remove_buff", target, buff_id, caster, remove_scope)
	if not bool(r.get("ok", false)):
		return {"ok": false, "error": r.get("error", "remove_buff_failed")}
	if _event_bus != null:
		_event_bus.emit_event(EventNames.BUFF_REMOVED, {
			"skill_id": "",
			"item_id": ctx.get("item_id", ""),
			"caster_id": int(caster.entity_id),
			"target_id": int(target.entity_id),
			"buff_id": buff_id,
			"remove_scope": remove_scope,
		})
	return {"ok": true}


func _get_unit_by_id(entity_id: int) -> Node:
	if _grid != null and ("_units" in _grid):
		var arr_any: Variant = _grid.get("_units")
		if typeof(arr_any) == TYPE_ARRAY:
			var arr: Array = arr_any
			for u in arr:
				if u != null and int(u.get("entity_id")) == entity_id:
					return u
	var stub = UnitStub.new()
	stub.entity_id = entity_id
	return stub


func _get_unit_by_cell_or_fallback(cell: Vector2i, fallback: Node) -> Node:
	if _grid != null and ("_units" in _grid):
		var arr_any: Variant = _grid.get("_units")
		if typeof(arr_any) == TYPE_ARRAY:
			var arr: Array = arr_any
			for u in arr:
				if u == null:
					continue
				if Vector2i(u.get("cell")) == cell:
					return u
	return fallback

