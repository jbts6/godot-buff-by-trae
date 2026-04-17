extends RefCounted
class_name OmniBuffAdapter

## OmniBuff 集成适配层：
## - 所有 buff/伤害相关调用都从这里走
## - damage 必须走 OmniBuff.DamagePipeline（优先 deal_damage，必要时兜底 deal_damage_v1）
## - simulate_* 不落地，仅返回预测描述

var ds = null
var enums_rt = null
var runtime_dict: Dictionary = {}

var pipe = null
var replay = null

func setup(dataset, enums_runtime, runtime: Dictionary) -> void:
	ds = dataset
	enums_rt = enums_runtime
	runtime_dict = runtime
	pipe = OmniDamagePipeline.new()
	replay = OmniReplay.new()


func deal_damage(caster, target, base_damage: float, ctx: Dictionary) -> Dictionary:
	if pipe == null:
		return {"ok": false, "error": "omnibuff_not_initialized"}

	var turn_index := int(ctx.get("turn_index", 0))
	var roll_key := int(ctx.get("roll_key", 0))
	var tags_mask := int(ctx.get("tags_mask", 0))
	var damage_type := int(ctx.get("damage_type", 0))
	var element := int(ctx.get("element", 0))
	var is_bonus_damage := bool(ctx.get("is_bonus_damage", false))

	# 约定：skill_id_int 可由上层传入；缺失时使用 -1（omnibuff 内部允许）
	var skill_id_int := int(ctx.get("skill_id_int", -1))

	# 将字符串枚举映射为 int（若 enums_rt 可用）
	if enums_rt != null:
		var dt = ctx.get("damage_type", 0)
		if typeof(dt) == TYPE_STRING:
			damage_type = int(enums_rt.enum_int("damage_type", String(dt)))
		var el = ctx.get("element", 0)
		if typeof(el) == TYPE_STRING:
			element = int(enums_rt.enum_int("element", String(el)))
		var tags = ctx.get("tags", [])
		if typeof(tags) == TYPE_ARRAY:
			tags_mask = int(enums_rt.tag_mask(tags))

	# Stats/Buffs 取自 Unit 字段契约
	var attacker_stats = caster.stats
	var defender_stats = target.stats
	var buff_attacker = caster.buffs
	var buff_defender = target.buffs

	if pipe.has_method("deal_damage"):
		var dctx = pipe.deal_damage(
			attacker_stats,
			defender_stats,
			buff_attacker,
			buff_defender,
			ds,
			base_damage,
			replay,
			turn_index,
			tags_mask,
			runtime_dict,
			roll_key,
			skill_id_int,
			damage_type,
			element,
			is_bonus_damage
		)
		return {
			"ok": true, 
			"final_damage": float(dctx.final_damage), 
			"meta": {
				"used": "deal_damage",
				"turn_index": turn_index,
				"roll_key": roll_key,
				"tags_mask": tags_mask,
				"damage_type": damage_type,
				"element": element,
				"is_bonus_damage": is_bonus_damage,
				"skill_id_int": skill_id_int
			}
		}

	# 兜底：旧签名（不含 is_bonus_damage）
	if pipe.has_method("deal_damage_v1"):
		var dctx_v1 = pipe.deal_damage_v1(
			attacker_stats,
			defender_stats,
			buff_attacker,
			buff_defender,
			ds,
			base_damage,
			replay,
			turn_index,
			tags_mask,
			runtime_dict,
			roll_key,
			skill_id_int,
			damage_type,
			element
		)
		return {
			"ok": true, 
			"final_damage": float(dctx_v1.final_damage), 
			"meta": {
				"used": "deal_damage_v1",
				"turn_index": turn_index,
				"roll_key": roll_key,
				"tags_mask": tags_mask,
				"damage_type": damage_type,
				"element": element,
				"is_bonus_damage": false,
				"skill_id_int": skill_id_int
			}
		}

	return {"ok": false, "error": "omnibuff_damage_pipeline_missing"}


func apply_buff(target_unit, buff_id: String, source_unit) -> Dictionary:
	if target_unit == null or target_unit.buffs == null or target_unit.stats == null:
		return {"ok": false, "error": "invalid_target_unit"}
	var inst_id := int(target_unit.buffs.apply_buff(target_unit.stats, buff_id, int(source_unit.entity_id)))
	if inst_id < 0:
		return {"ok": false, "error": "apply_buff_failed", "inst_id": inst_id}
	return {"ok": true, "inst_id": inst_id, "buff_id": buff_id}


func remove_buff(target_unit, buff_id: String, source_unit, remove_scope := "ALL") -> Dictionary:
	if target_unit == null or target_unit.buffs == null or target_unit.stats == null:
		return {"ok": false, "error": "invalid_target_unit"}
	var removed := int(target_unit.buffs.remove_by_buff_id(target_unit.stats, buff_id, remove_scope, int(source_unit.entity_id), false, true))
	return {"ok": true, "removed": removed, "buff_id": buff_id}


func simulate_apply_buff(target_unit, buff_id: String, source_unit) -> Dictionary:
	return {"kind": "apply_buff", "buff_id": buff_id, "target_id": int(target_unit.entity_id), "source_id": int(source_unit.entity_id)}


func simulate_remove_buff(target_unit, buff_id: String, source_unit, remove_scope := "ALL") -> Dictionary:
	return {"kind": "remove_buff", "buff_id": buff_id, "target_id": int(target_unit.entity_id), "source_id": int(source_unit.entity_id), "remove_scope": remove_scope}

func heal(caster, target, amount: float, ctx: Dictionary) -> Dictionary:
	var turn_index := int(ctx.get("turn_index", 0))
	var roll_key := int(ctx.get("roll_key", 0))
	var skill_id_int := int(ctx.get("skill_id_int", -1))
	var tags_mask := int(ctx.get("tags_mask", 0))
	
	# 如果 omnibuff 提供了 heal 管线，这里优先调用
	if pipe != null and pipe.has_method("heal"):
		# 假设存在类似于 deal_damage 的签名
		var dctx = pipe.heal(
			caster.stats,
			target.stats,
			caster.buffs,
			target.buffs,
			ds,
			amount,
			replay,
			turn_index,
			tags_mask,
			runtime_dict,
			roll_key,
			skill_id_int
		)
		return {"ok": true, "final_heal": float(dctx.get("final_heal", amount)), "meta": {"used": "pipe.heal"}}
	
	# 若无，则使用 heal_v1 最小一致性实现
	if enums_rt == null or ds == null or target.stats == null:
		return {"ok": false, "error": "omnibuff_not_initialized"}
		
	var hp_id := int(ds.stat_id_to_int.get("HP", -1))
	if hp_id < 0:
		return {"ok": false, "error": "missing_hp_stat"}
		
	var max_hp_id := int(ds.stat_id_to_int.get("MAX_HP", -1))
	var max_hp := 99999.0
	if max_hp_id >= 0:
		max_hp = target.stats.get_final(max_hp_id)
		
	var current_hp := float(target.stats.get_final(hp_id))
	var final_heal := amount
	
	if current_hp + final_heal > max_hp:
		final_heal = max_hp - current_hp
		if final_heal < 0:
			final_heal = 0
			
	if final_heal > 0:
		target.stats.add_base(hp_id, final_heal)
		
	if replay != null:
		if replay.has_method("push_heal_trace"):
			replay.push_heal_trace({
				"turn_index": turn_index,
				"target_id": int(target.entity_id),
				"source_id": int(caster.entity_id),
				"amount": final_heal,
				"skill_id_int": skill_id_int
			})
		elif replay.has_method("push_trace"):
			replay.push_trace("HEAL", {
				"turn_index": turn_index,
				"target_id": int(target.entity_id),
				"source_id": int(caster.entity_id),
				"amount": final_heal,
				"skill_id_int": skill_id_int
			})
		
	return {"ok": true, "final_heal": final_heal, "meta": {"used": "heal_v1", "original_amount": amount}}
