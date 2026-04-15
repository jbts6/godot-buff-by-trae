extends GutTest

## 用例：多段攻击（递增 base_damage）应产生递增的 final_damage，并且扣血结果可预测
##
## 目的：
## - 避免“第二段错误执行为第一段”等串段问题
## - 用断言替代肉眼观察控制台输出

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_multihit_damage_is_increasing_and_hp_matches() -> void:
	var loaded := TestDataset.load_base_demo(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	# attacker: ATK=10 + equip(20) => 30
	var a := TestBattle.make_entity(1001, ds, enums_rt)
	a.buffs.apply_buff(a.stats, "buff_equip_weapon_001", 1001)

	# defender: DEF default=5, HP default=100
	var d := TestBattle.make_entity(1002, ds, enums_rt)
	var runtime := TestBattle.make_runtime([a, d])

	# 让 filters.tag_mask_any 可命中（如果未来你给测试加更多触发器，也不会静默不触发）
	# 显式类型：避免 Godot 4 在某些场景下对 `:=` 推断失败
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var base_hits := [12.0, 14.0, 18.0]
	var finals := []
	for i in range(base_hits.size()):
		var ctx := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, float(base_hits[i]), replay, 10 + i, tags_mask, runtime)
		finals.append(float(ctx.final_damage))

	# 断言：三段递增（避免串段执行）
	assert_gt(finals[1], finals[0], "hit2 should be > hit1")
	assert_gt(finals[2], finals[1], "hit3 should be > hit2")

	# 数值断言：final = base + ATK - DEF = base + 25 => 37/39/43
	assert_eq(finals[0], 37.0)
	assert_eq(finals[1], 39.0)
	assert_eq(finals[2], 43.0)

	# HP 断言：HP = 100 - sum(final)
	var hp_id := ds.stat_id("HP")
	var expected_hp := 100.0 - (37.0 + 39.0 + 43.0)
	# C：StatsCore 现在会按 stat_defs(min/max) 进行 clamp，因此这里也要按同一规则计算期望值
	var hp_def: Dictionary = ds.stat_defs[hp_id]
	if bool(hp_def.get("clamp", false)):
		expected_hp = clamp(expected_hp, float(hp_def.get("min", expected_hp)), float(hp_def.get("max", expected_hp)))
	assert_eq(float(d.stats.get_final(hp_id)), expected_hp)
