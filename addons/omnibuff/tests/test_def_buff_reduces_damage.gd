extends GutTest

## 用例：防守方 DEF Buff（DEF+20）应降低每段最终伤害
##
## 目的：
## - 验证“防守 Buff”通过 StatCache/Modifier 聚合生效
## - 用明确的数值断言避免肉眼误判

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")

func test_def_buff_reduces_each_hit_damage() -> void:
	var loaded := OmniTestDataset.load_base_demo(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	# attacker: ATK=10 + equip(20) => 30
	var a := OmniTestBattle.make_entity(2001, ds, enums_rt)
	a.buffs.apply_buff(a.stats, "buff_equip_weapon_001", 2001)

	# defender: DEF default=5 + def_buff(20) => 25
	var d := OmniTestBattle.make_entity(2002, ds, enums_rt)
	d.buffs.apply_buff(d.stats, "buff_def_up_20_3t", 2002)

	var runtime := OmniTestBattle.make_runtime([a, d])
	var tags_mask := enums_rt.tag_mask(["BUFF"])

	var base_hits := [12.0, 14.0, 18.0]
	var finals := []
	for i in range(base_hits.size()):
		var ctx := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, float(base_hits[i]), replay, 20 + i, tags_mask, runtime)
		finals.append(float(ctx.final_damage))

	# 期望：final = base + ATK - DEF = base + 5 => 17/19/23
	assert_eq(finals[0], 17.0)
	assert_eq(finals[1], 19.0)
	assert_eq(finals[2], 23.0)

