class_name OmniSetDefs
extends RefCounted

## 轻量 set defs 容器（可选）
##
## 主要用于把 Dictionary 形式的 set_defs 变得更“可读/可校验”。
## 本插件核心逻辑不强依赖该类；你也可以直接传 Dictionary。

var defs: Dictionary = {} # set_id:String -> thresholds:Dictionary[int, String]

func _init(d: Dictionary = {}) -> void:
	defs = d

func has_set(set_id: String) -> bool:
	return defs.has(set_id)

func thresholds(set_id: String) -> Dictionary:
	return defs.get(set_id, {})

