extends Node

func _ready() -> void:
	print("[OmniBuffDemo] boot")
	# 注意：这是最小可运行 demo，用于验证：
	# - manifest/enums 加载成功（strict）
	# - stat_id/buff_id 编译映射可用
	# - StatCache dirty 行为正确
	# - Buff 注入 modifier 时只标脏对应 stat（不遍历全buff）
	# - DamagePipeline 阶段点触发事件时，只遍历 EventIndex 子集
	var result := OmniManifestLoader.load_dataset("res://data/base_demo/manifest.json", true)
	for issue in result.issues:
		push_error("%s %s %s %s: %s" % [issue.level, issue.file, issue.loc, issue.id, issue.message])
	print("[OmniBuffDemo] manifest loaded, enums keys=", result.enums.keys())
	var enums_rt := OmniEnumsRuntime.from_enums_json(result.enums)
	var sources := {
		"stat_defs": OmniJson.load_dict("res://data/base_demo/stat_defs.json"),
		"buff_defs": OmniJson.load_dict("res://data/base_demo/buff_defs.json")
	}
	var ds := OmniDatasetCompiler.compile(result.manifest, enums_rt, sources)
	print("[OmniBuffDemo] stat_id(ATK)=", ds.stat_id("ATK"), " buff_id(buff_atk_up_3t)=", ds.buff_id("buff_atk_up_3t"))

	var atk := ds.stat_id("ATK")
	var s := OmniStatsComponent.new(1, ds)
	print("[OmniBuffDemo] ATK1=", s.get_final(atk))
	s.add_base(atk, 5.0)
	print("[OmniBuffDemo] ATK2=", s.get_final(atk))
	print("[OmniBuffDemo] ATK3(no recompute)=", s.get_final(atk))

	var buff := OmniBuffCore.new(ds, enums_rt)
	print("[OmniBuffDemo] ATK(before equip buff)=", s.get_final(atk))
	buff.apply_buff(s, "buff_equip_weapon_001", s.entity_id)
	print("[OmniBuffDemo] ATK(after equip buff)=", s.get_final(atk))

	# 伤害Pipeline + EventIndex 验证：
	# attacker默认ATK=10，装备后ATK=30；base_damage=20；BEFORE_DEAL触发 +5 => base=25；def=5 => final=50；HP:100->50
	var attacker := OmniStatsComponent.new(101, ds)
	var buff_attacker := OmniBuffCore.new(ds, enums_rt)
	buff_attacker.apply_buff(attacker, "buff_equip_weapon_001", attacker.entity_id)
	buff_attacker.apply_buff(attacker, "buff_test_before_deal_plus5", attacker.entity_id)
	var defender := OmniStatsComponent.new(202, ds)
	var buff_defender := OmniBuffCore.new(ds, enums_rt)
	var pipe := OmniDamagePipeline.new()
	var ctx := pipe.deal_damage(attacker, defender, buff_attacker, buff_defender, ds, 20.0)
	print("[OmniBuffDemo] deal_damage final_damage=", ctx.final_damage, " defender_hp=", defender.get_final(ds.stat_id("HP")))

	# DOT（按来源独立实例）+ TurnEnd tick 验证：
	# - 两个来源对同一目标施加同种DOT（灼烧）
	# - 每跳读取来源当前ATK（StatCache），计算 dmg=ATK*base_ratio
	# - DOT默认在 TURN_END 结算，持续3回合
	var src_a := OmniStatsComponent.new(301, ds)
	var src_a_buff := OmniBuffCore.new(ds, enums_rt)
	src_a_buff.apply_buff(src_a, "buff_equip_weapon_001", src_a.entity_id) # ATK=30

	var src_b := OmniStatsComponent.new(302, ds)
	var src_b_buff := OmniBuffCore.new(ds, enums_rt)
	src_b_buff.apply_buff(src_b, "buff_equip_weapon_001", src_b.entity_id) # ATK=30
	src_b.add_base(ds.stat_id("ATK"), 20.0) # 让B更强：ATK=50

	var target := OmniStatsComponent.new(303, ds)
	var target_buff := OmniBuffCore.new(ds, enums_rt)

	# 同种DOT按来源独立实例：两次施加会创建两个 DotInstance
	target_buff.apply_buff(target, "buff_dot_fire_3t", src_a.entity_id)
	target_buff.apply_buff(target, "buff_dot_fire_3t", src_b.entity_id)

	var stats_by_entity := {
		301: src_a,
		302: src_b,
		303: target
	}
	var buff_by_entity := {
		301: src_a_buff,
		302: src_b_buff,
		303: target_buff
	}
	var turn := OmniTurnComponent.new()
	var ids := PackedInt32Array([301, 302, 303])
	ids.sort()

	for i in range(3):
		turn.on_turn_end(ids, buff_by_entity, stats_by_entity, pipe, ds)
		print("[OmniBuffDemo] DOT tick#", i + 1, " target_hp=", target.get_final(ds.stat_id("HP")))

	# 驱散（M7）最小验证：
	# - 给目标加一个显式增益（食物ATK+20，tag=BUFF）
	# - 再按 tag=BUFF 驱散：应移除显式buff，但默认不影响隐式装备buff
	var dispel_target := OmniStatsComponent.new(401, ds)
	var dispel_target_buff := OmniBuffCore.new(ds, enums_rt)
	dispel_target_buff.apply_buff(dispel_target, "buff_equip_weapon_001", 999) # IMPLICIT，ATK+20
	dispel_target_buff.apply_buff(dispel_target, "buff_food_atk_20_5t", 999)  # EXPLICIT，ATK+20
	print("[OmniBuffDemo] Dispel: ATK(before)=", dispel_target.get_final(ds.stat_id("ATK")))
	print(dispel_target_buff.debug_dump_instances())
	print(dispel_target_buff.debug_dump_stat_modifiers(dispel_target, ds.stat_id("ATK")))
	var removed := dispel_target_buff.dispel_by_tag(dispel_target, "BUFF", false)
	print("[OmniBuffDemo] Dispel: removed=", removed, " ATK(after)=", dispel_target.get_final(ds.stat_id("ATK")))
	print(dispel_target_buff.debug_dump_instances())
	print(dispel_target_buff.debug_dump_stat_modifiers(dispel_target, ds.stat_id("ATK")))
