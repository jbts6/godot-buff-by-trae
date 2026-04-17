extends RefCounted
class_name DemoUnit

## 最小 Unit 字段契约：
## - entity_id/camp/cell/stats/buffs

var entity_id: int
var camp: String
var cell: Vector2i
var stats
var buffs

func _init(eid: int, c: String, p: Vector2i, s, b) -> void:
	entity_id = eid
	camp = c
	cell = p
	stats = s
	buffs = b
