extends RefCounted
class_name SkillRuntime

const SkillDB := preload("res://addons/turn_skill_system/runtime/skill_db.gd")
const TargetingRegistry := preload("res://addons/turn_skill_system/runtime/targeting/targeting_registry.gd")
const EffectRegistry := preload("res://addons/turn_skill_system/runtime/effects/effect_registry.gd")
const BattleEventBus := preload("res://addons/turn_skill_system/runtime/battle_event_bus.gd")
const OmniBuffAdapter := preload("res://addons/turn_skill_system/runtime/omni_buff_adapter.gd")
const EventNames := preload("res://addons/turn_skill_system/runtime/event_names.gd")
const Grid := preload("res://addons/turn_skill_system/runtime/grid.gd")
const Formula := preload("res://addons/turn_skill_system/runtime/formula.gd")

const AUTOLOAD_NAME := "TurnSkillRuntime"

## --- Public API (固定，不可改名) ---

static func cast(skill_id: String, caster, primary_cell = null, extra: Dictionary = {}) -> Dictionary:
	return _cast_internal(false, skill_id, caster, primary_cell, extra)

static func simulate_cast(skill_id: String, caster, primary_cell = null, extra: Dictionary = {}) -> Dictionary:
	return _cast_internal(true, skill_id, caster, primary_cell, extra)

static func cast_to_unit(skill_id: String, caster, primary_target, extra: Dictionary = {}) -> Dictionary:
	if primary_target == null:
		return {"ok": false, "simulation": false, "skill_id": skill_id, "caster_id": _safe_id(caster), "errors": ["primary_target_is_null"]}
	return cast_to_cell(skill_id, caster, Vector2i(primary_target.cell), extra)

static func cast_to_cell(skill_id: String, caster, primary_cell: Vector2i, extra: Dictionary = {}) -> Dictionary:
	var cell := Vector2i(primary_cell)
	if cell.x < 0 or cell.x > 2 or cell.y < 0 or cell.y > 2:
		return {"ok": false, "simulation": false, "skill_id": skill_id, "caster_id": _safe_id(caster), "errors": ["primary_cell_out_of_range"]}
	return cast(skill_id, caster, cell, extra)


## --- Internal ---

static func _cast_internal(simulation: bool, skill_id: String, caster, primary_cell, extra: Dictionary) -> Dictionary:
	var rt := _get_runtime(extra)
	if rt.has("error"):
		return _fail(simulation, skill_id, caster, [String(rt.get("error", "runtime_error"))])

	var event_bus: BattleEventBus = rt["event_bus"]
	event_bus.begin_capture()

	var rng_seed := int(extra.get("rng_seed", 0))

	event_bus.emit_event(EventNames.SKILL_CAST_STARTED, {
		"skill_id": skill_id,
		"caster_id": _safe_id(caster),
		"simulation": simulation,
	})

	var sr: Dictionary = rt["db"].get_skill(skill_id, true)
	if not bool(sr.get("ok", false)):
		return _fail(simulation, skill_id, caster, sr.get("errors", []), event_bus.end_capture(), rng_seed, sr.get("issues", []))
	var skill: Dictionary = sr.get("skill", {})

	if String(skill.get("type", "")) != "active":
		return _fail(simulation, skill_id, caster, ["skill_type_not_active"], event_bus.end_capture(), rng_seed)

	# 目标选择
	var targets: Array = rt["targeting"].resolve(skill, caster, primary_cell, rt["grid"], extra)
	if targets.is_empty():
		return _fail(simulation, skill_id, caster, ["no_valid_targets"], event_bus.end_capture(), rng_seed)

	var out_targets: Array = []
	for t in targets:
		var cell: Vector2i = t.get("cell", Vector2i(-1, -1))
		out_targets.append({"unit_id": int(t.get("unit_id", -1)), "cell": [int(cell.x), int(cell.y)]})

	var resolved_formulas: Array = []
	var out_effects: Array = []
	var predicted_deltas: Array = []

	# omnibuff 初始化（必须：damage 走 pipeline）
	if extra.has("dataset") and extra.has("enums_rt") and extra.has("runtime_dict"):
		rt["omnibuff"].setup(extra.dataset, extra.enums_rt, extra.runtime_dict)
	elif not simulation:
		# simulate 不强制（只返回预测）
		return _fail(simulation, skill_id, caster, ["missing_omnibuff_context(dataset/enums_rt/runtime_dict)"], event_bus.end_capture(), rng_seed)

	# on_cast（执行一次；target 取第一个目标供部分效果使用）
	var primary_target = targets[0].get("unit", null)
	for e in skill.get("on_cast", []):
		var ctx := _make_ctx(skill, skill_id, caster, primary_target, rt, extra, rng_seed)
		var er: Dictionary = rt["effects"].apply_effect(e, ctx, simulation)
		_collect_effect_result(er, out_effects, predicted_deltas, resolved_formulas, simulation, ctx)

	# 命中参数（兼容 rpg_tests/skill_defs.json）
	var hit_count := int(skill.get("hit_count", 1))
	if hit_count <= 0:
		hit_count = 1
	var hit_base_damage = skill.get("hit_base_damage", [])
	var base_damage_fallback := float(skill.get("base_damage", 0.0))

	# 若 on_hit 为空但存在 base_damage/hit_base_damage：隐式补一个 damage effect
	var on_hit_effects: Array = skill.get("on_hit", [])
	var implicit_damage := false
	if on_hit_effects.is_empty() and (base_damage_fallback > 0.0 or (typeof(hit_base_damage) == TYPE_ARRAY and hit_base_damage.size() > 0)):
		implicit_damage = true

	for t in targets:
		var target_unit = t.get("unit", null)
		for hit_index in range(hit_count):
			var hit_damage := base_damage_fallback
			if typeof(hit_base_damage) == TYPE_ARRAY and hit_index < hit_base_damage.size():
				var hd = hit_base_damage[hit_index]
				if typeof(hd) == TYPE_STRING:
					var fr := Formula.eval_expr(String(hd), _make_ctx(skill, skill_id, caster, target_unit, rt, extra, rng_seed), "floor")
					if bool(fr.get("ok", false)):
						hit_damage = float(fr.get("value", hit_damage))
						resolved_formulas.append(fr.get("resolved", {}))
				else:
					hit_damage = float(hd)

			var ctx_hit := _make_ctx(skill, skill_id, caster, target_unit, rt, extra, rng_seed)
			ctx_hit["hit_index"] = hit_index
			ctx_hit["hit_count"] = hit_count
			ctx_hit["hit_base_damage"] = hit_damage

			if implicit_damage:
				var dmg_effect := {"kind": "damage", "params": {"amount": hit_damage}}
				var er0: Dictionary = rt["effects"].apply_effect(dmg_effect, ctx_hit, simulation)
				_collect_effect_result(er0, out_effects, predicted_deltas, resolved_formulas, simulation, ctx_hit)

			for e_hit in on_hit_effects:
				var e2 = e_hit
				# 若 damage effect 未提供 amount/amount_expr，则用当前段 hit_damage
				if typeof(e2) == TYPE_DICTIONARY and String(e2.get("kind", "")) == "damage":
					var p: Dictionary = e2.get("params", {})
					if not p.has("amount") and not p.has("amount_expr"):
						var copy: Dictionary = e2.duplicate(true) as Dictionary
						copy["params"]["amount"] = hit_damage
						e2 = copy
				var er: Dictionary = rt["effects"].apply_effect(e2, ctx_hit, simulation)
				_collect_effect_result(er, out_effects, predicted_deltas, resolved_formulas, simulation, ctx_hit)

	event_bus.emit_event(EventNames.SKILL_CAST_FINISHED, {
		"skill_id": skill_id,
		"caster_id": _safe_id(caster),
		"targets": out_targets,
		"simulation": simulation,
	})

	var events := event_bus.end_capture()

	return {
		"ok": true,
		"simulation": simulation,
		"skill_id": skill_id,
		"caster_id": _safe_id(caster),
		"targets": out_targets,
		"effects": out_effects,
		"resolved_formulas": resolved_formulas,
		"events": events,
		"rng_seed": rng_seed,
		"errors": [],
		"predicted_deltas": predicted_deltas if simulation else [],
	}


static func _make_ctx(skill: Dictionary, skill_id: String, caster, target, rt: Dictionary, extra: Dictionary, rng_seed: int) -> Dictionary:
	# 公式上下文（a/t）只暴露纯数据（默认空），由上层填充 extra.a_stats/extra.t_stats
	return {
		"skill_id": skill_id,
		"skill": skill,
		"caster": caster,
		"target": target,
		"grid": rt["grid"],
		"event_bus": rt["event_bus"],
		"omnibuff": rt["omnibuff"],
		"turn_index": int(extra.get("turn_index", 0)),
		"roll_key": int(extra.get("roll_key", 0)),
		"rng_seed": rng_seed,
		"damage_type": skill.get("damage_type", 0),
		"element": skill.get("element", 0),
		"tags": skill.get("tags", []),
		"tags_mask": int(extra.get("tags_mask", 0)),
		"skill_id_int": int(extra.get("skill_id_int", -1)),
		"a_stats": extra.get("a_stats", {}),
		"t_stats": extra.get("t_stats", {}),
	}


static func _collect_effect_result(er: Dictionary, out_effects: Array, predicted_deltas: Array, resolved_formulas: Array, simulation: bool, ctx: Dictionary) -> void:
	if er == null:
		return
	if er.has("resolved_formulas") and typeof(er.resolved_formulas) == TYPE_ARRAY:
		for x in er.resolved_formulas:
			resolved_formulas.append(x)

	if not bool(er.get("ok", false)):
		out_effects.append({"kind": "error", "value": 0, "meta": {"error": er.get("error", "effect_failed")}})
		return

	if er.has("kind"):
		var k := String(er.get("kind", ""))
		out_effects.append({"kind": k, "value": er.get("value", 0), "meta": er.get("meta", {})})
		if simulation:
			predicted_deltas.append({
				"kind": k,
				"value": er.get("value", 0),
				"caster_id": _safe_id(ctx.get("caster")),
				"target_id": _safe_id(ctx.get("target")),
			})


static func _get_runtime(extra: Dictionary) -> Dictionary:
	var al = _get_autoload()
	if al != null:
		al.ensure_ready()
		return {
			"db": al.db,
			"event_bus": al.event_bus,
			"targeting": al.targeting,
			"effects": al.effects,
			"omnibuff": al.omnibuff,
			"grid": extra.get("grid", al.grid),
		}

	# fallback：允许从 extra 注入
	if extra.has("db") and extra.has("event_bus") and extra.has("targeting") and extra.has("effects") and extra.has("omnibuff") and extra.has("grid"):
		return {
			"db": extra.db,
			"event_bus": extra.event_bus,
			"targeting": extra.targeting,
			"effects": extra.effects,
			"omnibuff": extra.omnibuff,
			"grid": extra.grid,
		}

	# 最小构造（用于纯脚本 quick test）
	var db := SkillDB.new()
	db.reload_index()
	var event_bus := BattleEventBus.new()
	var targeting := TargetingRegistry.new()
	targeting.register_defaults()
	var effects := EffectRegistry.new()
	effects.register_defaults()
	var omnibuff := OmniBuffAdapter.new()
	var grid := Grid.new()
	return {
		"db": db,
		"event_bus": event_bus,
		"targeting": targeting,
		"effects": effects,
		"omnibuff": omnibuff,
		"grid": grid,
	}


static func _get_autoload():
	var ml = Engine.get_main_loop()
	if ml == null:
		return null
	if not (ml is SceneTree):
		return null
	var root := (ml as SceneTree).root
	if root == null:
		return null
	if not root.has_node("/root/" + AUTOLOAD_NAME):
		return null
	return root.get_node("/root/" + AUTOLOAD_NAME)


static func _fail(simulation: bool, skill_id: String, caster, errors: Array, events: Array = [], rng_seed: int = 0, issues: Array = []) -> Dictionary:
	return {
		"ok": false,
		"simulation": simulation,
		"skill_id": skill_id,
		"caster_id": _safe_id(caster),
		"targets": [],
		"effects": [],
		"resolved_formulas": [],
		"events": events,
		"rng_seed": rng_seed,
		"errors": errors,
		"issues": issues,
	}


static func _safe_id(u) -> int:
	if u == null:
		return -1
	if u.has_property("entity_id"):
		return int(u.entity_id)
	return -1
