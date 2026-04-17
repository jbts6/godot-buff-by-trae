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
	# 注意：这里不要用 `:=` 让编译器推断类型；默认空数组 `[]` 会导致推断失败。
	var stat_defs: Array = sources.get("stat_defs", {}).get("stats", [])
	for i in range(stat_defs.size()):
		var s: Dictionary = stat_defs[i]
		ds.stat_id_to_int[String(s["id"])] = i
		ds.stat_defs.append(s)

	# Phase 2：derived graph compile（最小实现：以 stat_defs 的 derived 字段生成依赖图与 topo_order）
	var n := ds.stat_defs.size()
	ds.derived_defs_by_stat.resize(n)
	ds.derived_inputs_by_stat.resize(n)
	ds.derived_dependents_by_stat.resize(n)
	for i in range(n):
		ds.derived_defs_by_stat[i] = {}
		ds.derived_inputs_by_stat[i] = PackedInt32Array()
		ds.derived_dependents_by_stat[i] = PackedInt32Array()

	for sid in range(n):
		var sdef: Dictionary = ds.stat_defs[sid]
		if not sdef.has("derived"):
			continue
		var d: Dictionary = sdef.get("derived", {})
		if typeof(d) != TYPE_DICTIONARY:
			continue
		ds.derived_defs_by_stat[sid] = d
		var inputs := PackedInt32Array()
		var seen_dep := {}
		var dt := String(d.get("type", "")).to_upper()
		if dt == "LINEAR":
			var from_name := String(d.get("from", ""))
			var from_id := int(ds.stat_id(from_name))
			if from_id >= 0 and (not seen_dep.has(from_id)):
				seen_dep[from_id] = true
				inputs.append(from_id)
		elif dt == "EXPR":
			for name in d.get("inputs", []):
				var dep_name := String(name)
				var dep := int(ds.stat_id(dep_name))
				if dep >= 0 and (not seen_dep.has(dep)):
					seen_dep[dep] = true
					inputs.append(dep)
		ds.derived_inputs_by_stat[sid] = inputs
		for dep in inputs:
			var arr_dep: PackedInt32Array = ds.derived_dependents_by_stat[int(dep)]
			arr_dep.append(int(sid))
			ds.derived_dependents_by_stat[int(dep)] = arr_dep

	# topo sort (Kahn) + cycle detect
	var indeg := PackedInt32Array()
	indeg.resize(n)
	for sid in range(n):
		indeg[sid] = 0
	for sid in range(n):
		for dep in ds.derived_inputs_by_stat[sid]:
			indeg[sid] += 1

	var q: Array[int] = []
	for sid in range(n):
		if indeg[sid] == 0:
			q.append(sid)

	var order := PackedInt32Array()
	while not q.is_empty():
		var cur := int(q.pop_front())
		order.append(cur)
		for nxt in ds.derived_dependents_by_stat[cur]:
			indeg[int(nxt)] -= 1
			if indeg[int(nxt)] == 0:
				q.append(int(nxt))
	if order.size() != n:
		# 循环依赖：留空 topo_order（validators 应阻断）
		order = PackedInt32Array()
	ds.derived_topo_order = order

	# buffs
	var buff_defs: Array = sources.get("buff_defs", {}).get("buffs", [])
	for i in range(buff_defs.size()):
		var b: Dictionary = buff_defs[i]
		ds.buff_id_to_int[String(b["id"])] = i
		ds.buff_defs.append(b)

	return ds
