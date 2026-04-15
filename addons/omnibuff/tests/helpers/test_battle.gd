class_name OmniTestBattle
extends RefCounted

## 测试 helper：构造最小 battle runtime（供 APPLY_BUFF/CHANCE_APPLY_BUFF 使用）
##
## runtime = {
##   "stats_by_entity": { eid: OmniStatsComponent },
##   "buff_by_entity":  { eid: OmniBuffCore }
## }
##
## 注意：
## - 使用 Dictionary 以避免测试阶段引入更多全局类/强类型依赖。
## - 这里的“实体”是纯数据结构，不依赖场景树。

static func make_entity(eid: int, ds: OmniCompiledDataset, enums_rt: OmniEnumsRuntime) -> Dictionary:
	var stats := OmniStatsComponent.new(eid, ds)
	var buffs := OmniBuffCore.new(ds, enums_rt)
	return {"eid": eid, "stats": stats, "buffs": buffs}

static func make_runtime(entities: Array) -> Dictionary:
	var stats_by := {}
	var buff_by := {}
	for e in entities:
		stats_by[int(e.eid)] = e.stats
		buff_by[int(e.eid)] = e.buffs
	return {"stats_by_entity": stats_by, "buff_by_entity": buff_by}

