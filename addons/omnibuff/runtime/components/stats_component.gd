class_name OmniStatsComponent
extends RefCounted

## 面向 Entity/Actor 的 Stats 组件（OOP封装）
##
## 说明：
## - 本组件是一个轻量“外壳”，核心缓存逻辑在 `OmniStatsCore`
## - 运行时热路径应持有组件引用，并只通过 `get_final()` 读取最终值

## StatCache 内核（包含 base/final/dirty 与 per-stat modifier 列表）
var core: OmniStatsCore

## 实体ID（不依赖场景树；用于追帧/索引/回放）
var entity_id: int

func _init(eid: int, dataset: OmniCompiledDataset) -> void:
	entity_id = eid
	core = OmniStatsCore.new(dataset)

func get_final(stat_id: int) -> float:
	return core.get_final(stat_id)

func add_base(stat_id: int, dv: float) -> void:
	core.add_base(stat_id, dv)

func get_breakdown(stat_id: int) -> Dictionary:
	return core.get_breakdown(stat_id)
