class_name OmniStatsCore
extends RefCounted

## StatCache + DirtyFlags（最小可用版）
##
## - 运行时热路径只允许通过 `get_final(stat_id)` 读取属性
## - 任何属性变动（base变化 / buff注入 / buff撤销）必须 `mark_dirty(stat_id)`
## - 当前实现支持：
##   - ADD/FLAT：平铺加成（base + flat）
##   - MUL/PERCENT：百分比加成（最终按 (base + flat) * (1 + pct) 计算）
##   后续会扩展 apply_phase（BASE/CONVERT/FLAT/PERCENT/FINAL/CLAMP）与 priority 排序

## 编译后的数据集（只读）：提供 stat_defs / 映射表等
var ds: OmniCompiledDataset

## 基础值（base stat），长度=stat_count
var base_values: PackedFloat32Array

## 最终值缓存（final stat snapshot），长度=stat_count
var final_values: PackedFloat32Array

## 脏标记：1表示需要重算，0表示缓存可直接读，长度=stat_count
var dirty: PackedByteArray

## 每个 stat 的 modifier 列表（由 BuffCore 在 buff 变动时维护）
## - 索引：stat_id
## - 元素：任意对象
##   - 新格式：包含字段 `op`/`phase`/`value`（以及可选兼容字段 add_value）
##   - 旧格式：仅包含字段 `add_value`（视作 ADD/FLAT）
var modifiers_by_stat: Array = []

func _init(dataset: OmniCompiledDataset) -> void:
	ds = dataset
	var n := ds.stat_defs.size()
	base_values = PackedFloat32Array()
	base_values.resize(n)
	final_values = PackedFloat32Array()
	final_values.resize(n)
	dirty = PackedByteArray()
	dirty.resize(n)
	modifiers_by_stat.resize(n)
	for i in range(n):
		base_values[i] = float(ds.stat_defs[i].get("default", 0.0))
		final_values[i] = base_values[i]
		dirty[i] = 0
		modifiers_by_stat[i] = []

func set_base(stat_id: int, v: float) -> void:
	# 设置基础值（会使该stat缓存失效）
	base_values[stat_id] = v
	dirty[stat_id] = 1

func add_base(stat_id: int, dv: float) -> void:
	# 增量修改基础值（例如扣血/加盾/成长变化）
	base_values[stat_id] += dv
	dirty[stat_id] = 1

func mark_dirty(stat_id: int) -> void:
	# 由 BuffCore/外部系统调用：表示该stat受影响需要重算
	dirty[stat_id] = 1

func recompute(stat_id: int) -> void:
	# 重算一个 stat 的最终值
	# 注意：这里遍历的是“该 stat 的 modifier 聚合列表”，不是遍历全部 BuffInstance
	var base := base_values[stat_id]
	var flat := 0.0
	var pct_by_layer: Dictionary = {} # int -> float（percent layers）
	var final_add := 0.0
	var has_override := false
	var override_v := 0.0
	var override_pri := -2147483648
	var override_src := -2147483648
	for m in modifiers_by_stat[stat_id]:
		# 当前约定：BuffCore 注入的 modifier 一定是 OmniModifierRef（包含 op/phase/value）。
		# 这里不依赖 class_name 的全局类表，只依赖字段名存在。
		if m == null or typeof(m) != TYPE_OBJECT:
			continue
		var op := String(m.op)
		var ph := String(m.phase)
		var val := float(m.value)
		var pri := int(m.priority)
		var src := int(m.source_inst_id)
		if op == "ADD" and ph == "FLAT":
			flat += val
		elif op == "MUL" and ph == "PERCENT":
			# layer 缺省为 0（OmniModifierRef 默认字段）；旧数据保持兼容
			var layer: int = int(m.layer)
			if not pct_by_layer.has(layer):
				pct_by_layer[layer] = 0.0
			pct_by_layer[layer] = float(pct_by_layer[layer]) + val
		elif op == "ADD" and ph == "FINAL":
			final_add += val
		elif op == "OVERRIDE" and ph == "FINAL":
			if (not has_override) or (pri > override_pri) or (pri == override_pri and src > override_src):
				has_override = true
				override_pri = pri
				override_src = src
				override_v = val

	var v := (base + flat)
	if not pct_by_layer.is_empty():
		var layers: Array = pct_by_layer.keys()
		layers.sort()
		for l in layers:
			v *= (1.0 + float(pct_by_layer[l]))
	if has_override:
		v = override_v
	v += final_add

	var def: Dictionary = ds.stat_defs[stat_id]
	if bool(def.get("clamp", false)):
		v = clamp(v, float(def.get("min", v)), float(def.get("max", v)))
	final_values[stat_id] = v

func get_final(stat_id: int) -> float:
	# 热路径读取：若脏则重算一次，然后返回快照
	if dirty[stat_id] == 1:
		recompute(stat_id)
		dirty[stat_id] = 0
	return final_values[stat_id]
