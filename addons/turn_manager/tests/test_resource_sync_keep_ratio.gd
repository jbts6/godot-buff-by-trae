extends GutTest

const TurnManager = preload("res://addons/turn_manager/runtime/turn_manager.gd")
const BattleContext = preload("res://addons/turn_manager/runtime/battle_context.gd")


class FakeDataset extends RefCounted:
	var _stat_name_to_id: Dictionary = {}
	
	func _init() -> void:
		_stat_name_to_id["HP"] = 0
		_stat_name_to_id["MAX_HP"] = 1
		_stat_name_to_id["MP"] = 2
		_stat_name_to_id["MAX_MP"] = 3
		_stat_name_to_id["RAGE"] = 4
		_stat_name_to_id["MAX_RAGE"] = 5
	
	func stat_id(name: String) -> int:
		return int(_stat_name_to_id.get(name, -1))


class FakeStats extends RefCounted:
	var _values: Dictionary = {}
	
	func get_final(stat_id_int: int) -> float:
		return float(_values.get(stat_id_int, 0.0))
	
	func add_base(stat_id_int: int, delta: float) -> void:
		_values[stat_id_int] = float(_values.get(stat_id_int, 0.0)) + delta


class DummyUnit extends Node:
	var entity_id: int = 0
	var stats: FakeStats = null


func _object_has_property(obj: Object, prop_name: String) -> bool:
	var plist = obj.get_property_list()
	for p in plist:
		if String(p.get("name", "")) == prop_name:
			return true
	return false


func test_sync_keep_ratio_floor_half_to_121() -> void:
	# 用例：old_max=100 old_cur=50 new_max=121
	# 期望：new_cur=floor(0.5*121)=60
	var tm = TurnManager.new()
	
	var has_sync = tm.has_method("sync_resources_keep_ratio")
	assert_true(has_sync, "TurnManager 应提供 sync_resources_keep_ratio(actor) 以同步资源条百分比（当前/最大）")
	if not has_sync:
		tm.free()
		return
	
	var has_snapshot_prop = _object_has_property(tm, "resource_snapshot_by_entity")
	assert_true(has_snapshot_prop, "TurnManager 应提供 resource_snapshot_by_entity 用于记录 old_max 快照")
	if not has_snapshot_prop:
		tm.free()
		return
	
	var ds = FakeDataset.new()
	var ctx = BattleContext.new()
	ctx.dataset = ds
	tm._context = ctx
	
	var u = DummyUnit.new()
	u.entity_id = 1001
	u.stats = FakeStats.new()
	
	var hp_id = ds.stat_id("HP")
	var max_hp_id = ds.stat_id("MAX_HP")
	u.stats.add_base(hp_id, 50.0)
	u.stats.add_base(max_hp_id, 121.0)
	
	# 手动注入快照：old_max=100（同步前记录的 MAX）
	var snapshot_by_entity: Dictionary = {}
	snapshot_by_entity[u.entity_id] = {}
	snapshot_by_entity[u.entity_id][max_hp_id] = 100.0
	tm.set("resource_snapshot_by_entity", snapshot_by_entity)
	
	tm.call("sync_resources_keep_ratio", u)
	
	var new_hp = u.stats.get_final(hp_id)
	assert_eq(int(new_hp), 60, "当 MAX_HP 从 100 变为 121 时，应保持 50% 并 floor 到 60")
	
	u.free()
	tm.free()


func test_sync_keep_ratio_within_turn_max_hp_changes_to_200() -> void:
	# 用例：同一回合内 MAX 变化
	# 先同步一次建立快照：HP=50 MAX_HP=100
	# 然后把 MAX_HP 改为 200（stats.add_base），再次同步
	# 期望：HP 变为 floor(0.5*200)=100
	var tm = TurnManager.new()
	
	var has_sync = tm.has_method("sync_resources_keep_ratio")
	assert_true(has_sync, "TurnManager 应提供 sync_resources_keep_ratio(actor) 以同步资源条百分比（当前/最大）")
	if not has_sync:
		tm.free()
		return
	
	var ds = FakeDataset.new()
	var ctx = BattleContext.new()
	ctx.dataset = ds
	tm._context = ctx
	
	var u = DummyUnit.new()
	u.entity_id = 1002
	u.stats = FakeStats.new()
	
	var hp_id = ds.stat_id("HP")
	var max_hp_id = ds.stat_id("MAX_HP")
	u.stats.add_base(hp_id, 50.0)
	u.stats.add_base(max_hp_id, 100.0)
	
	# 第一次同步：建立快照（old_max=100），HP 不应变化
	tm.call("sync_resources_keep_ratio", u)
	assert_eq(int(u.stats.get_final(hp_id)), 50, "首次同步建立快照时，HP 应保持不变")
	
	# 回合内 MAX 变化：MAX_HP 100 -> 200
	u.stats.add_base(max_hp_id, 100.0)
	tm.call("sync_resources_keep_ratio", u)
	
	var new_hp = u.stats.get_final(hp_id)
	assert_eq(int(new_hp), 100, "当 MAX_HP 从 100 变为 200 时，应保持 50% 并 floor 到 100")
	
	u.free()
	tm.free()


func test_sync_keep_ratio_within_turn_max_mp_changes_to_41() -> void:
	# 再补一例：MP/MAX_MP 比例保持（同回合 MAX 变化）
	# MP=10 MAX_MP=20 -> 同步建立快照
	# MAX_MP 改为 41（+21）后再次同步
	# 期望：MP=floor(0.5*41)=20
	var tm = TurnManager.new()
	
	var has_sync = tm.has_method("sync_resources_keep_ratio")
	assert_true(has_sync, "TurnManager 应提供 sync_resources_keep_ratio(actor) 以同步资源条百分比（当前/最大）")
	if not has_sync:
		tm.free()
		return
	
	var ds = FakeDataset.new()
	var ctx = BattleContext.new()
	ctx.dataset = ds
	tm._context = ctx
	
	var u = DummyUnit.new()
	u.entity_id = 1003
	u.stats = FakeStats.new()
	
	var mp_id = ds.stat_id("MP")
	var max_mp_id = ds.stat_id("MAX_MP")
	u.stats.add_base(mp_id, 10.0)
	u.stats.add_base(max_mp_id, 20.0)
	
	tm.call("sync_resources_keep_ratio", u)
	assert_eq(int(u.stats.get_final(mp_id)), 10, "首次同步建立快照时，MP 应保持不变")
	
	u.stats.add_base(max_mp_id, 21.0)
	tm.call("sync_resources_keep_ratio", u)
	
	var new_mp = u.stats.get_final(mp_id)
	assert_eq(int(new_mp), 20, "当 MAX_MP 从 20 变为 41 时，应保持 50% 并 floor 到 20")
	
	u.free()
	tm.free()
