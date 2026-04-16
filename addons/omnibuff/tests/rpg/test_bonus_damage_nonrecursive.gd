extends GutTest

## 追加伤害（不递归）验收：
## - 原伤害触发一次 BONUS_DAMAGE
## - BONUS_DAMAGE 造成的伤害不会再次触发 BONUS_DAMAGE（trace 不会爆炸）

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const Executor := preload("res://addons/omnibuff/runtime/core/battle_executor.gd")
const CommandContext := preload("res://addons/omnibuff/runtime/core/command_context.gd")
const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")


func test_bonus_damage_should_not_recurse() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var sources: Dictionary = loaded.result.sources

	var pipe := OmniDamagePipeline.new()
	var exec := Executor.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 9501
	var defender_id := 9502
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	# attacker：每次造成伤害追加 3 点伤害（且不递归）
	attacker.buffs.apply_buff(attacker.stats, "buff_bonus_damage_3_nonrecursive", attacker_id)

	var cmd := CommandContext.new()
	cmd.actor_id = attacker_id
	cmd.command_kind = "ATTACK"
	cmd.targets = PackedInt32Array([defender_id])
	cmd.skill_id = 1 # skill_basic_attack_1

	var before := int(replay.damage_traces.size())
	exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, replay)
	var after := int(replay.damage_traces.size())
	assert_eq(after - before, 2, "should produce exactly 2 damage traces (base + bonus), no recursion")

