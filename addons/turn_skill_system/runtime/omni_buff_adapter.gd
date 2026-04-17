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
		return {"ok": true, "final_damage": float(dctx.final_damage), "meta": {"used": "deal_damage"}}

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
		return {"ok": true, "final_damage": float(dctx_v1.final_damage), "meta": {"used": "deal_damage_v1"}}

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
