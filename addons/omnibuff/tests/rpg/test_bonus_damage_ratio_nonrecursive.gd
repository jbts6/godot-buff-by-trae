extends GutTest

## BONUS_DAMAGE ratio 验收：bonus.base_damage = base.final_damage * ratio，且不递归

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const Executor := preload("res://addons/omnibuff/runtime/core/battle_executor.gd")
const CommandContext := preload("res://addons/omnibuff/runtime/core/command_context.gd")
const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")


func test_bonus_damage_ratio_should_use_final_damage() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var sources: Dictionary = loaded.result.sources
	var pipe := OmniDamagePipeline.new()
	var exec := Executor.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 9601
	var defender_id := 9602
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	attacker.buffs.apply_buff(attacker.stats, "buff_bonus_damage_ratio_50p_nonrecursive", attacker_id)

	var cmd := CommandContext.new()
	cmd.actor_id = attacker_id
	cmd.command_kind = "ATTACK"
	cmd.targets = PackedInt32Array([defender_id])
	cmd.skill_id = 1

	var before := int(replay.damage_traces.size())
	exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, replay)
	var after := int(replay.damage_traces.size())
	assert_eq(after - before, 2)

	var t0 = replay.damage_traces[before + 0]
	var t1 = replay.damage_traces[before + 1]
	var expected := float(t0.final_damage) * 0.5
	assert_true(abs(float(t1.base_damage) - expected) < 0.0001)

