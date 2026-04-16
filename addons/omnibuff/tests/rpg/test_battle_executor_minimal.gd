extends GutTest

## BattleExecutor（最小可用）验收：
## - 普攻（BASIC_ATTACK）能触发 DAMAGE/BEFORE_DEAL 的“普攻加成”
## - ESCAPE 能被 COMMAND/CMD_BEFORE 的 CANCEL_COMMAND 取消
## - USE_ITEM 能触发 COMMAND filters（item_id）

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const Executor := preload("res://addons/omnibuff/runtime/core/battle_executor.gd")
const CommandContext := preload("res://addons/omnibuff/runtime/core/command_context.gd")
const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")


func _count_instances_by_buff_id(buffs: RefCounted, ds: OmniCompiledDataset, buff_id_str: String) -> int:
	var cnt: int = 0
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		var def: Dictionary = ds.buff_defs[int(inst.buff_def_id)]
		if String(def.get("id", "")) == buff_id_str:
			cnt += 1
	return cnt


func test_executor_attack_basic_attack_bonus_applies() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var sources: Dictionary = loaded.result.sources

	var pipe := OmniDamagePipeline.new()
	var exec := Executor.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 9201
	var defender_id := 9202
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	# 给攻击者挂“普攻加成：+5 base”
	attacker.buffs.apply_buff(attacker.stats, "buff_basic_attack_add_base_5", attacker_id)

	var cmd := CommandContext.new()
	cmd.actor_id = attacker_id
	cmd.command_kind = "ATTACK"
	cmd.targets = PackedInt32Array([defender_id])
	# 约定：skill_id 作为 skill_defs.skills 的索引（最小实现）
	# skill_basic_attack_1 在 rpg_tests/skill_defs.json 中是第 2 个（index=1）
	cmd.skill_id = 1

	var res = exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, replay)
	assert_false(bool(res.canceled))
	assert_not_null(res.last_damage_ctx)
	assert_true(float(res.last_damage_ctx.base_damage) >= 5.0, "basic attack bonus should increase base_damage")


func test_executor_escape_can_be_canceled() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var sources: Dictionary = loaded.result.sources

	var pipe := OmniDamagePipeline.new()
	var exec := Executor.new()

	var actor_id := 9211
	var actor := TestBattle.make_entity(actor_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([actor])

	actor.buffs.apply_buff(actor.stats, "buff_cmd_cancel_escape", actor_id)

	var cmd := CommandContext.new()
	cmd.actor_id = actor_id
	cmd.command_kind = "ESCAPE"

	var res = exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, null)
	assert_true(bool(res.canceled))
	assert_false(bool(res.escaped))


func test_executor_use_item_triggers_item_id_filters() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var sources: Dictionary = loaded.result.sources

	var pipe := OmniDamagePipeline.new()
	var exec := Executor.new()

	var actor_id := 9221
	var actor := TestBattle.make_entity(actor_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([actor])

	actor.buffs.apply_buff(actor.stats, "buff_cmd_use_item_mark", actor_id)

	var cmd := CommandContext.new()
	cmd.actor_id = actor_id
	cmd.command_kind = "USE_ITEM"
	cmd.item_id = 2001

	var res = exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, null)
	assert_false(bool(res.canceled))
	assert_true(_count_instances_by_buff_id(actor.buffs, ds, "buff_dummy_mark_1") >= 1, "use_item should apply mark via COMMAND filter")

