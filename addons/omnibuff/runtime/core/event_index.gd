class_name OmniEventIndex
extends RefCounted

const PHASE_COUNT := 16

# key = event_type_int * PHASE_COUNT + phase_int
var listeners: Array[PackedInt32Array] = []

class Listener:
	var key: int
	var inst_id: int
	var filter_tag_mask: int
	var action_kind: String
	var action_value: float

var listener_data: Array[Listener] = []

func _init(event_key_count: int) -> void:
	listeners.resize(event_key_count)
	for i in range(event_key_count):
		listeners[i] = PackedInt32Array()

func register_listener(key: int, l: Listener) -> int:
	l.key = key
	var id := listener_data.size()
	listener_data.append(l)
	listeners[key].append(id)
	return id

func get_listeners_for(key: int) -> PackedInt32Array:
	return listeners[key]

