class_name OmniTurnComponent
extends RefCounted

## Turn 编排组件（最小可用版）
##
## 职责：
## - 提供 TurnStart/TurnEnd 两阶段 tick 的“稳定调用顺序”
## - 本插件不实现完整战斗框架（行动队列/AI/UI），这里只提供 tick 编排工具
##
## 稳定性要求（用于本地复盘）：
## - 对实体列表必须按 entity_id 升序调用
## - 对 DOT/BUFF 到期处理必须按 inst_id/dot_inst_id 升序（由 BuffCore 内部保证）

var turn_index: int = 1

func on_turn_start(entity_ids_sorted: PackedInt32Array, buff_by_entity: Dictionary) -> void:
	# 当前版本未实现 TurnStart tick（DOT默认在TurnEnd结算），先留接口以保持结构完整
	for eid in entity_ids_sorted:
		var b = buff_by_entity.get(int(eid), null)
		if b != null and b.has_method("on_turn_start"):
			b.on_turn_start(turn_index)

func on_turn_end(entity_ids_sorted: PackedInt32Array, buff_by_entity: Dictionary, stats_by_entity: Dictionary, pipeline: OmniDamagePipeline, ds: OmniCompiledDataset, replay: OmniReplay = null) -> void:
	# TurnEnd tick：对每个实体依次处理其 Buff/DOT（稳定顺序）
	for eid in entity_ids_sorted:
		var b = buff_by_entity.get(int(eid), null)
		if b != null and b.has_method("on_turn_end"):
			# 约定：on_turn_end(turn_index, stats_by_entity, buff_by_entity, pipeline, ds, replay)
			# replay 为可选参数：用于追帧，不影响逻辑
			b.on_turn_end(turn_index, stats_by_entity, buff_by_entity, pipeline, ds, replay)
	turn_index += 1
