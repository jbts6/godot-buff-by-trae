class_name OmniEventIndex
extends RefCounted

## EventIndex：事件索引（性能关键）
##
## 目标：
## - 事件触发时只遍历“监听该事件的子集”，而不是遍历所有 BuffInstance
## - key = event_type_int * PHASE_COUNT + phase_int
## - listeners[key] 存 listener_id 列表

const PHASE_COUNT := 16

## 监听列表池：索引为 key，值为 listener_id 的紧凑列表
var listeners: Array[PackedInt32Array] = []

class Listener:
	## 缓存 key（便于将来注销/迁移）
	var key: int
	## 监听者所属的 buff inst_id（用于追帧/调试/未来驱散后注销）
	var inst_id: int
	## 是否生效（驱散/到期后可设为 false；emit_event 应跳过 inactive）
	var active: bool = true
	## 过滤器：要求 ctx.tags_mask 至少命中一个 bit（0表示不做tag过滤）
	var filter_tag_mask: int
	## 动作类型（当前最小实现：ADD_BASE_DAMAGE）
	var action_kind: String
	## 动作参数（例如 +5）
	var action_value: float

## listener_id -> Listener 数据（按注册顺序增长）
var listener_data: Array[Listener] = []

func _init(event_key_count: int) -> void:
	listeners.resize(event_key_count)
	for i in range(event_key_count):
		listeners[i] = PackedInt32Array()

func register_listener(key: int, l: Listener) -> int:
	## 注册一个 listener，返回 listener_id
	l.key = key
	var id := listener_data.size()
	listener_data.append(l)
	listeners[key].append(id)
	return id

func get_listeners_for(key: int) -> PackedInt32Array:
	## 获取该事件key对应的监听者列表（子集遍历入口）
	return listeners[key]
