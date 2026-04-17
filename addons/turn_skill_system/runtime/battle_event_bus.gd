extends RefCounted
class_name BattleEventBus

signal event_emitted(event_type: String, data: Dictionary)

var _capture_enabled := false
var _captured_events: Array[Dictionary] = []

func begin_capture() -> void:
	_capture_enabled = true
	_captured_events.clear()

func end_capture() -> Array[Dictionary]:
	_capture_enabled = false
	return _captured_events.duplicate(true)

func emit_event(event_type: String, data: Dictionary) -> void:
	if _capture_enabled:
		_captured_events.append({"type": event_type, "data": data})
	event_emitted.emit(event_type, data)

