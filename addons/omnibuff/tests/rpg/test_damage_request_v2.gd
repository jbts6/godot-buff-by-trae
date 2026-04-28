extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _setup() -> Dictionary:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var enums_rt := OmniEnumsRuntime.from_enums_json(res.enums)
	var ds := OmniDatasetCompiler.compile(res.manifest, enums_rt, res.sources)
	var pipe := OmniDamagePipeline.new()
	var replay := OmniReplay.new()
	var a := TestBattle.make_entity(101, ds, enums_rt)
	var d := TestBattle.make_entity(202, ds, enums_rt)
	var runtime := TestBattle.make_runtime([a, d])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	return {
		"enums_rt": enums_rt, "ds": ds, "pipe": pipe, "replay": replay,
		"a": a, "d": d, "runtime": runtime, "tags_mask": tags_mask
	}


func test_v2_produces_same_result_as_deal_damage() -> void:
	var s := _setup()
	var ctx1 = s.pipe.deal_damage(s.a.stats, s.d.stats, s.a.buffs, s.d.buffs, s.ds, 20.0, s.replay, 1, s.tags_mask, s.runtime)
	var req := OmniDamagePipeline.make_request(s.a.stats, s.d.stats, s.a.buffs, s.d.buffs, s.ds, 20.0)
	req["replay"] = s.replay
	req["turn_index"] = 1
	req["tags_mask"] = s.tags_mask
	req["runtime"] = s.runtime
	var ctx2 = s.pipe.deal_damage_v2(req)
	assert_eq(ctx2.final_damage, ctx1.final_damage, "v2 final_damage should match deal_damage")


func test_v2_produces_same_result_as_v1() -> void:
	var s := _setup()
	var ctx1 = s.pipe.deal_damage_v1(s.a.stats, s.d.stats, s.a.buffs, s.d.buffs, s.ds, 20.0, s.replay, 1, s.tags_mask, s.runtime)
	var req := OmniDamagePipeline.make_request(s.a.stats, s.d.stats, s.a.buffs, s.d.buffs, s.ds, 20.0)
	req["replay"] = s.replay
	req["turn_index"] = 1
	req["tags_mask"] = s.tags_mask
	req["runtime"] = s.runtime
	var ctx2 = s.pipe.deal_damage_v2(req)
	assert_eq(ctx2.final_damage, ctx1.final_damage, "v2 final_damage should match v1")


func test_v2_with_optional_fields() -> void:
	var s := _setup()
	var req := OmniDamagePipeline.make_request(s.a.stats, s.d.stats, s.a.buffs, s.d.buffs, s.ds, 25.0)
	req["turn_index"] = 5
	req["roll_key"] = 3
	req["skill_id"] = 0
	req["damage_type"] = 1
	req["element"] = 2
	req["tags_mask"] = s.tags_mask
	req["runtime"] = s.runtime
	var ctx = s.pipe.deal_damage_v2(req)
	assert_ne(ctx, null, "v2 should return non-null context")
	assert_eq(ctx.skill_id, 0)
	assert_eq(ctx.damage_type, 1)
	assert_eq(ctx.element, 2)


func test_make_request_contains_required_fields() -> void:
	var s := _setup()
	var req := OmniDamagePipeline.make_request(s.a.stats, s.d.stats, s.a.buffs, s.d.buffs, s.ds, 30.0)
	assert_true(req.has("attacker"))
	assert_true(req.has("defender"))
	assert_true(req.has("buff_attacker"))
	assert_true(req.has("buff_defender"))
	assert_true(req.has("ds"))
	assert_eq(req["base_damage"], 30.0)
