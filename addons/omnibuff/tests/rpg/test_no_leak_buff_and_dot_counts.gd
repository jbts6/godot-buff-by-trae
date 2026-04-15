extends GutTest

## J plan / Task2：回归测试 - 驱散后不应泄露 buff/dot 计数
##
## 循环流程（每轮）：
## 1) attacker 三连造成 DOT（AFTER_DEAL -> APPLY_BUFF）
## 2) TurnEnd / TurnStart 推进并 tick（DOT 为 TURN_START 语义）
## 3) defender.dispel_by_tag("DEBUFF") 驱散
## 4) 断言：
##    - defender.buffs.inst_ids.size() == 0
##    - defender.buffs.dots_by_target[defender_id] 为空或不存在
##
## 注意：避免使用 `:=` 的推断（在动态对象/Variant 上容易踩坑）

const ReplayScript = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid: int = int(ds.stat_id(stat_name))
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v))


func _assert_dots_empty_or_missing(defender: Dictionary, defender_id: int) -> void:
	var dots_any: Variant = defender.buffs.dots_by_target.get(defender_id, null)
	if dots_any == null:
		return
	var dots: Array = dots_any
	assert_eq(int(dots.size()), 0, "dots_by_target[%s] should be empty after dispel" % [defender_id])


func test_no_leak_buff_and_dot_counts_after_dispel_in_loop() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()
	var turn = OmniTurnComponent.new()

	var attacker_id: int = 9101
	var defender_id: int = 9102

	var attacker = TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender = TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime = TestBattle.make_runtime([attacker, defender])

	# 稳定性：固定命中/暴击/闪避，避免随机性影响挂 DOT 与 tick 逻辑
	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)

	# attacker：每次命中后给目标挂 DOT（MULTI_INSTANCE）
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_apply_dot", attacker_id)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var entity_ids: PackedInt32Array = PackedInt32Array([attacker_id, defender_id])
	entity_ids.sort()

	var base_hits: Array = [12.0, 14.0, 18.0]
	var loops: int = 6

	for k in range(loops):
		# 1) 三连：每段 AFTER_DEAL 都应挂 1 个 DOT buff 实例
		for i in range(base_hits.size()):
			pipe.deal_damage(
				attacker.stats,
				defender.stats,
				attacker.buffs,
				defender.buffs,
				ds,
				float(base_hits[i]),
				replay,
				1000 + k * 10 + i,
				tags_mask,
				runtime
			)

		assert_eq(int(defender.buffs.inst_ids.size()), 3, "loop=%s: defender should have 3 buff instances after 3 hits" % [k])

		# 2) 推进回合并 tick（TURN_START 语义）
		turn.on_turn_end(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
		turn.on_turn_start(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

		# 3) 驱散 DEBUFF
		var before_dispel: int = int(defender.buffs.inst_ids.size())
		var removed: int = int(defender.buffs.dispel_by_tag(defender.stats, "DEBUFF", false))
		assert_eq(removed, before_dispel, "loop=%s: dispel should remove all defender buff instances" % [k])

		# 4) 断言无泄露
		assert_eq(int(defender.buffs.inst_ids.size()), 0, "loop=%s: defender.inst_ids should be empty after dispel" % [k])
		_assert_dots_empty_or_missing(defender, defender_id)
