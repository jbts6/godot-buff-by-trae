class_name OmniCompiledDataset
extends RefCounted

## 编译后的数据集（运行时只读）
##
## 重要：运行时核心（Stats/Buff/Damage）不允许依赖原始JSON/CSV字段名，
## 只允许依赖这里的“编译后内存结构”（int索引、数组、bitmask）。
##
## 当前为“最小可用版”，仍使用 `Array[Dictionary]` 直通保存 defs，
## 后续会按性能需要改成 Packed*Array/紧凑结构体池。

## 源数据fingerprint（用于复盘一致性测试/缓存有效性；当前未计算，先占位）
var fingerprint: String = ""

## Stat 字符串ID -> int 索引（stat_id）
var stat_id_to_int: Dictionary = {}

## Stat 定义数组：index=stat_id；元素为定义字典（后续改为紧凑结构）
var stat_defs: Array[Dictionary] = []

## Buff 字符串ID -> int 索引（buff_def_id）
var buff_id_to_int: Dictionary = {}

## Buff 定义数组：index=buff_def_id；元素为定义字典（后续改为紧凑结构）
var buff_defs: Array[Dictionary] = []

func stat_id(id_str: String) -> int:
	# 返回 stat_id；不存在返回 -1（加载期应由校验器阻断/报警）
	return int(stat_id_to_int.get(id_str, -1))

func buff_id(id_str: String) -> int:
	# 返回 buff_def_id；不存在返回 -1（加载期应由校验器阻断/报警）
	return int(buff_id_to_int.get(id_str, -1))
