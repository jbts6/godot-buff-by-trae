class_name OmniReplay
extends RefCounted

## 本地回放/追帧（M8，最小可用版）
##
## 目标：
## - 记录“输入命令流”（cast skill / use item / equip change / 等）
## - 记录“追帧信息”（每次伤害 DamageTrace、每次DOT跳伤 DotTrace）
## - 仅要求同版本同设备可复盘：稳定执行顺序 + 显式记录关键输入
##
## 注意：
## - 本文件只提供“记录与导出”的最小功能；完整“重放执行器”后续可扩展
## - 追帧记录不用于驱动逻辑，仅用于调试/一致性校验

enum CommandType { CAST_SKILL, USE_ITEM, EQUIP_CHANGE, END_TURN }

class Command:
	extends RefCounted
	## 命令类型（CAST_SKILL/USE_ITEM/...)
	var type: int
	## 回合号（从1开始）
	var turn: int
	## 执行者实体ID（actor）
	var actor_id: int
	## 技能/道具/装备ID（字符串；更适合数据驱动与可读性）
	var id_str: String
	## 目标列表（稳定顺序：entity_id 升序）
	var targets: PackedInt32Array = PackedInt32Array()
	## 随机种子/偏移（最小占位；真实项目可用 deterministic RNG）
	var rng_seed_delta: int = 0

class DamageTrace:
	extends RefCounted
	## 回合号
	var turn: int
	## 攻击方/防守方实体
	var attacker_id: int
	var defender_id: int
	## ctx 输入/输出
	var base_damage: float
	var final_damage: float
	## tags_mask（用于解释 filters 命中情况）
	var tags_mask: int
	## 触发的 buff inst_id 列表（按发生顺序拼接）
	var triggered_inst_ids: PackedInt32Array = PackedInt32Array()
	## 分阶段触发列表：stage -> inst_id[]
	var stage_triggers: Dictionary = {}

class DotTrace:
	extends RefCounted
	## 回合号
	var turn: int
	## DOT实例ID（稳定排序用）
	var dot_inst_id: int
	## 归属 buff inst_id（用于追溯来源buff实例）
	var owner_buff_inst_id: int
	## 来源/目标
	var source_entity_id: int
	var target_entity_id: int
	## 读取到的来源属性快照（证明走了StatCache）
	var read_source_stat: String
	var source_stat_value: float
	## 计算参数与结果
	var base_ratio: float
	var base_damage: float
	var final_damage: float
	## tags_mask（DOT/FIRE等）
	var tags_mask: int

## 命令流（输入）
var commands: Array[Command] = []

## 伤害追帧（输出）
var damage_traces: Array[DamageTrace] = []

## DOT追帧（输出）
var dot_traces: Array[DotTrace] = []

func clear() -> void:
	commands.clear()
	damage_traces.clear()
	dot_traces.clear()

func record_cast_skill(turn: int, actor_id: int, skill_id: String, targets: PackedInt32Array, rng_seed_delta: int = 0) -> void:
	var c := Command.new()
	c.type = CommandType.CAST_SKILL
	c.turn = turn
	c.actor_id = actor_id
	c.id_str = skill_id
	c.targets = targets.duplicate()
	c.rng_seed_delta = rng_seed_delta
	commands.append(c)

func trace_damage(turn: int, ctx: RefCounted, triggered_inst_ids: PackedInt32Array, stage_triggers: Dictionary) -> void:
	## 记录一次伤害追帧
	## ctx 约定字段：attacker_id/defender_id/base_damage/final_damage/tags_mask
	var t := DamageTrace.new()
	t.turn = turn
	t.attacker_id = int(ctx.attacker_id)
	t.defender_id = int(ctx.defender_id)
	t.base_damage = float(ctx.base_damage)
	t.final_damage = float(ctx.final_damage)
	t.tags_mask = int(ctx.tags_mask)
	t.triggered_inst_ids = triggered_inst_ids.duplicate()
	t.stage_triggers = stage_triggers.duplicate(true)
	damage_traces.append(t)

func trace_dot_tick(turn: int, dot_inst_id: int, owner_buff_inst_id: int, source_entity_id: int, target_entity_id: int, read_source_stat: String, source_stat_value: float, base_ratio: float, base_damage: float, final_damage: float, tags_mask: int) -> void:
	## 记录一次DOT跳伤追帧
	var t := DotTrace.new()
	t.turn = turn
	t.dot_inst_id = dot_inst_id
	t.owner_buff_inst_id = owner_buff_inst_id
	t.source_entity_id = source_entity_id
	t.target_entity_id = target_entity_id
	t.read_source_stat = read_source_stat
	t.source_stat_value = source_stat_value
	t.base_ratio = base_ratio
	t.base_damage = base_damage
	t.final_damage = final_damage
	t.tags_mask = tags_mask
	dot_traces.append(t)

func debug_dump_last_damage() -> String:
	## 调试：输出最近一次伤害的追帧信息
	if damage_traces.is_empty():
		return "[DamageTrace] <empty>"
	var t: DamageTrace = damage_traces[damage_traces.size() - 1]
	return "[DamageTrace] turn=%s atk=%s def=%s base=%.2f final=%.2f triggered=%s" % [
		t.turn, t.attacker_id, t.defender_id, t.base_damage, t.final_damage, t.triggered_inst_ids
	]

func debug_dump_last_dot() -> String:
	## 调试：输出最近一次 DOT tick 的追帧信息
	if dot_traces.is_empty():
		return "[DotTrace] <empty>"
	var t: DotTrace = dot_traces[dot_traces.size() - 1]
	return "[DotTrace] turn=%s dot_inst=%s owner_buff_inst=%s src=%s tgt=%s read=%s=%.2f ratio=%.3f base=%.2f final=%.2f tags=%s" % [
		t.turn,
		t.dot_inst_id,
		t.owner_buff_inst_id,
		t.source_entity_id,
		t.target_entity_id,
		t.read_source_stat,
		t.source_stat_value,
		t.base_ratio,
		t.base_damage,
		t.final_damage,
		t.tags_mask
	]

func debug_dump_dot_range(from_index: int) -> String:
	## 调试：输出 dot_traces[from_index .. end) 的所有记录（每行一条）
	## 用途：
	## - 一个回合内可能有多个 DOT 来源（例如 301 与 302），每次 tick 会产生多条 DotTrace
	## - debug_dump_last_dot() 只能看到最后一条，因此用这个函数一次性打印新增的所有记录
	if from_index < 0:
		from_index = 0
	if from_index >= dot_traces.size():
		return "[DotTrace] <none>"
	var lines: Array[String] = []
	for i in range(from_index, dot_traces.size()):
		var t: DotTrace = dot_traces[i]
		lines.append("[DotTrace] turn=%s dot_inst=%s owner_buff_inst=%s src=%s tgt=%s read=%s=%.2f ratio=%.3f base=%.2f final=%.2f tags=%s" % [
			t.turn,
			t.dot_inst_id,
			t.owner_buff_inst_id,
			t.source_entity_id,
			t.target_entity_id,
			t.read_source_stat,
			t.source_stat_value,
			t.base_ratio,
			t.base_damage,
			t.final_damage,
			t.tags_mask
		])
	return "\n".join(lines)
