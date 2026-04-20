extends RefCounted
class_name Inventory

## 最小背包（独立系统）
## - 只维护 item_id -> count
## - 不涉及战斗 CD、分类、排序等

var _counts: Dictionary = {} # String -> int


func set_count(item_id: String, count: int) -> void:
	_counts[item_id] = maxi(0, int(count))


func add(item_id: String, delta: int) -> void:
	var cur: int = get_count(item_id)
	set_count(item_id, cur + int(delta))


func get_count(item_id: String) -> int:
	return int(_counts.get(item_id, 0))


func can_consume(item_id: String, amount: int = 1) -> bool:
	return get_count(item_id) >= int(amount)


func consume(item_id: String, amount: int = 1) -> Dictionary:
	var need = int(amount)
	if need <= 0:
		return {"ok": false, "error": "invalid_amount"}
	var cur = get_count(item_id)
	if cur < need:
		return {"ok": false, "error": "not_enough"}
	set_count(item_id, cur - need)
	return {"ok": true}

