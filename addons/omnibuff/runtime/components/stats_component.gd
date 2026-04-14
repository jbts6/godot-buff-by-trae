class_name OmniStatsComponent
extends RefCounted

var core: OmniStatsCore
var entity_id: int

func _init(eid: int, dataset: OmniCompiledDataset) -> void:
	entity_id = eid
	core = OmniStatsCore.new(dataset)

func get_final(stat_id: int) -> float:
	return core.get_final(stat_id)

func add_base(stat_id: int, dv: float) -> void:
	core.add_base(stat_id, dv)

