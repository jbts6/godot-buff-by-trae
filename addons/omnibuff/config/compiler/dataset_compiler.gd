class_name OmniDatasetCompiler
extends RefCounted

static func compile(manifest: Dictionary, enums_rt: OmniEnumsRuntime, sources: Dictionary) -> OmniCompiledDataset:
	## 编译 raw defs -> CompiledDataset（最小可用版）
	##
	## 约束：
	## - 这里是“Schema字段名”允许出现的边界（Parser/Compiler 层）
	## - 运行时核心（Stats/Buff/Damage）只允许读 OmniCompiledDataset
	##
	## 当前版本只编译：
	## - stat_defs.stats[] -> stat_id 映射 + defs数组
	## - buff_defs.buffs[] -> buff_id 映射 + defs数组
	var ds := OmniCompiledDataset.new()

	# stats
	var stat_defs := sources["stat_defs"].get("stats", [])
	for i in range(stat_defs.size()):
		var s: Dictionary = stat_defs[i]
		ds.stat_id_to_int[String(s["id"])] = i
		ds.stat_defs.append(s)

	# buffs
	var buff_defs := sources["buff_defs"].get("buffs", [])
	for i in range(buff_defs.size()):
		var b: Dictionary = buff_defs[i]
		ds.buff_id_to_int[String(b["id"])] = i
		ds.buff_defs.append(b)

	return ds
