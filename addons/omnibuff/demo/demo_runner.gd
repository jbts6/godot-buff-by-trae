extends Node

func _ready() -> void:
	print("[OmniBuffDemo] boot")
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
