extends GutTest

## BattleExecutor multi-hit / multi-target / roll_key 验收

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const Executor := preload("res://addons/omnibuff/runtime/core/battle_executor.gd")
const CommandContext := preload("res://addons/omnibuff/runtime/core/command_context.gd")
const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")


func _skill_index_by_id(sources: Dictionary, id_str: String) -> int:
	var skills: Array = sources.get("skill_defs", {}).get("skills", [])
	for i in range(skills.size()):
		var s: Dictionary = skills[i]
		if String(s.get("id", "")) == id_str:
			return i
	return -1


func test_executor_multihit_triple_slash_roll_key_increments() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var sources: Dictionary = loaded.result.sources

	var pipe := OmniDamagePipeline.new()
	var exec := Executor.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 9401
	var defender_id := 9402
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	var skill_idx := _skill_index_by_id(sources, "skill_triple_slash")
	assert_true(skill_idx >= 0, "missing skill_triple_slash in skill_defs")

	var before := replay.damage_traces.size()
	var cmd := CommandContext.new()
	cmd.actor_id = attacker_id
	cmd.command_kind = "CAST_SKILL"
	cmd.skill_id = skill_idx
	cmd.targets = PackedInt32Array([defender_id])

	exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, replay)
	var after := replay.damage_traces.size()
	assert_eq(after - before, 3, "triple slash should produce 3 damage traces")
	assert_eq(int(replay.damage_traces[before + 0].roll_key), 0)
	assert_eq(int(replay.damage_traces[before + 1].roll_key), 1)
	assert_eq(int(replay.damage_traces[before + 2].roll_key), 2)


func test_executor_multitarget_all_targets_sorted() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var sources: Dictionary = loaded.result.sources

	var pipe := OmniDamagePipeline.new()
	var exec := Executor.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 9411
	var a_id := 9413
	var b_id := 9412 # 故意给乱序
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var a := TestBattle.make_entity(a_id, ds, enums_rt)
	var b := TestBattle.make_entity(b_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, a, b])

	var skill_idx := _skill_index_by_id(sources, "skill_whirlwind")
	assert_true(skill_idx >= 0, "missing skill_whirlwind in skill_defs")

	var before := replay.damage_traces.size()
	var cmd := CommandContext.new()
	cmd.actor_id = attacker_id
	cmd.command_kind = "CAST_SKILL"
	cmd.skill_id = skill_idx
	cmd.targets = PackedInt32Array([a_id, b_id]) # 乱序输入

	exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, replay)
	var after := replay.damage_traces.size()
	assert_eq(after - before, 2, "ALL targeting should hit both targets once")
	# 应按 entity_id 升序
	assert_eq(int(replay.damage_traces[before + 0].defender_id), min(a_id, b_id))
	assert_eq(int(replay.damage_traces[before + 1].defender_id), max(a_id, b_id))


func test_executor_all_plus_two_hits_roll_key_order() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var sources: Dictionary = loaded.result.sources

	var pipe := OmniDamagePipeline.new()
	var exec := Executor.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 9421
	var a_id := 9423
	var b_id := 9422
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var a := TestBattle.make_entity(a_id, ds, enums_rt)
	var b := TestBattle.make_entity(b_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, a, b])

	var skill_idx := _skill_index_by_id(sources, "skill_double_strike_all")
	assert_true(skill_idx >= 0, "missing skill_double_strike_all in skill_defs")

	var before := replay.damage_traces.size()
	var cmd := CommandContext.new()
	cmd.actor_id = attacker_id
	cmd.command_kind = "CAST_SKILL"
	cmd.skill_id = skill_idx
	cmd.targets = PackedInt32Array([a_id, b_id])

	exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, replay)
	var after := replay.damage_traces.size()
	assert_eq(after - before, 4)
	# 目标排序：min -> max；每目标两段
	var first := min(a_id, b_id)
	var second := max(a_id, b_id)
	assert_eq(int(replay.damage_traces[before + 0].defender_id), first)
	assert_eq(int(replay.damage_traces[before + 1].defender_id), first)
	assert_eq(int(replay.damage_traces[before + 2].defender_id), second)
	assert_eq(int(replay.damage_traces[before + 3].defender_id), second)
	# roll_key: 0..3
	for i in range(4):
		assert_eq(int(replay.damage_traces[before + i].roll_key), i)

