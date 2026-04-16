class_name OmniSetBonusManager
extends RefCounted

## 套装加成管理器（完全解耦于 OmniBuff 内部）
##
## 职责：
## - 输入：equipped_items（装备列表，包含 set_id），set_defs（套装阈值->buff_id）
## - 输出：仅通过 BuffCore 的公开 API `apply_buff/remove_by_buff_id` 下发/撤销套装 buff
##
## 重要：不读取/不依赖 BuffCore 内部 inst_ids 等结构；幂等靠本类内部缓存实现。

## entity_id -> active buff ids（由本管理器负责维护的“当前套装buff列表”）
var _active_by_entity: Dictionary = {} # int -> PackedStringArray


static func compute_active_set_buffs(equipped_items: Array, set_defs: Dictionary) -> PackedStringArray:
	## 计算“应该生效”的套装 buff 列表（稳定排序、去重）
	##
	## equipped_items 约定：
	## - Array[Dictionary]，每个元素可包含：
	##   - set_id: String（缺失/空字符串表示不参与套装）
	##
	## set_defs 约定：
	## - Dictionary[String, Dictionary[int, String]]
	##   例如：{"dragon": {2:"set_dragon_2pc", 4:"set_dragon_4pc"}}
	var count_by_set: Dictionary = {} # set_id -> count
	for it in equipped_items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var set_id: String = String((it as Dictionary).get("set_id", ""))
		if set_id == "":
			continue
		count_by_set[set_id] = int(count_by_set.get(set_id, 0)) + 1

	var uniq: Dictionary = {} # buff_id -> true
	for set_id in count_by_set.keys():
		if not set_defs.has(set_id):
			continue
		var thresholds: Dictionary = set_defs[set_id]
		var n: int = int(count_by_set[set_id])
		for k in thresholds.keys():
			var th: int = int(k)
			if n >= th:
				var buff_id: String = String(thresholds[k])
				if buff_id != "":
					uniq[buff_id] = true

	var out := PackedStringArray()
	for buff_id in uniq.keys():
		out.append(String(buff_id))
	out.sort()
	return out


func refresh_entity(
	stats: RefCounted,
	buffs: RefCounted,
	equipped_items: Array,
	set_defs: Dictionary,
	source_entity_id: int
) -> void:
	## 幂等刷新：只根据 equipped_items 与 set_defs 计算 desired，然后对当前 active 做 diff。
	##
	## 依赖的最小接口：
	## - stats.entity_id: int
	## - buffs.apply_buff(stats, buff_id, source_entity_id)
	## - buffs.remove_by_buff_id(stats, buff_id, "ALL", -1, false, true)
	var eid: int = int(stats.entity_id)
	var desired: PackedStringArray = compute_active_set_buffs(equipped_items, set_defs)
	var prev: PackedStringArray = PackedStringArray(_active_by_entity.get(eid, PackedStringArray()))

	# add: desired - prev
	for buff_id in desired:
		if not prev.has(buff_id):
			buffs.apply_buff(stats, String(buff_id), source_entity_id)

	# remove: prev - desired
	for buff_id in prev:
		if not desired.has(buff_id):
			# force=true：套装属于“装备状态”，应可被可靠撤销
			buffs.remove_by_buff_id(stats, String(buff_id), "ALL", -1, false, true)

	_active_by_entity[eid] = desired


func clear_entity(stats: RefCounted, buffs: RefCounted) -> void:
	## 清空该实体的所有“套装buff”（仅清本管理器曾经下发的）
	var eid: int = int(stats.entity_id)
	var prev: PackedStringArray = PackedStringArray(_active_by_entity.get(eid, PackedStringArray()))
	for buff_id in prev:
		buffs.remove_by_buff_id(stats, String(buff_id), "ALL", -1, false, true)
	_active_by_entity.erase(eid)

