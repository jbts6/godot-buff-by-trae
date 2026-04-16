extends GutTest

## Phase 1：回合制 COMMAND 事件域扩展（验收）
##
## 覆盖：
## - COMMAND/CMD_BEFORE：CANCEL_COMMAND（禁止逃跑）
## - COMMAND/CMD_AFTER：tag_mask_any(BASIC_ATTACK) 命中
## - COMMAND/CMD_AFTER：item_id 过滤命中

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const CommandContext := preload("res://addons/omnibuff/runtime/core/command_context.gd")


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


func test_cancel_escape_command() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var actor_id := 9101
	var actor := TestBattle.make_entity(actor_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([actor])

	actor.buffs.apply_buff(actor.stats, "buff_cmd_cancel_escape", actor_id)

	var ctx := CommandContext.new()
	ctx.actor_id = actor_id
	ctx.command_kind = "ESCAPE"
	ctx.set_meta("runtime", runtime)

	actor.buffs.emit_event("COMMAND", "CMD_BEFORE", ctx)
	assert_true(bool(ctx.cancel), "escape command should be canceled")


func test_basic_attack_tag_filter_on_command() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var actor_id := 9111
	var actor := TestBattle.make_entity(actor_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([actor])

	actor.buffs.apply_buff(actor.stats, "buff_cmd_basic_attack_mark", actor_id)

	var ctx := CommandContext.new()
	ctx.actor_id = actor_id
	ctx.command_kind = "ATTACK"
	ctx.skill_id = 1001
	ctx.tags_mask = int(enums_rt.tag_mask(["BASIC_ATTACK"]))
	ctx.set_meta("runtime", runtime)

	actor.buffs.emit_event("COMMAND", "CMD_AFTER", ctx)
	assert_true(_count_instances_by_buff_id(actor.buffs, ds, "buff_dummy_mark_1") >= 1, "basic attack tag should apply mark")


func test_use_item_id_filter_on_command() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var actor_id := 9121
	var actor := TestBattle.make_entity(actor_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([actor])

	actor.buffs.apply_buff(actor.stats, "buff_cmd_use_item_mark", actor_id)

	var ctx_ok := CommandContext.new()
	ctx_ok.actor_id = actor_id
	ctx_ok.command_kind = "USE_ITEM"
	ctx_ok.item_id = 2001
	ctx_ok.set_meta("runtime", runtime)
	actor.buffs.emit_event("COMMAND", "CMD_AFTER", ctx_ok)
	assert_true(_count_instances_by_buff_id(actor.buffs, ds, "buff_dummy_mark_1") >= 1, "item_id=2001 should apply mark")

	# 反例：item_id 不匹配，不再追加 mark
	var before := _count_instances_by_buff_id(actor.buffs, ds, "buff_dummy_mark_1")
	var ctx_bad := CommandContext.new()
	ctx_bad.actor_id = actor_id
	ctx_bad.command_kind = "USE_ITEM"
	ctx_bad.item_id = 9999
	ctx_bad.set_meta("runtime", runtime)
	actor.buffs.emit_event("COMMAND", "CMD_AFTER", ctx_bad)
	var after := _count_instances_by_buff_id(actor.buffs, ds, "buff_dummy_mark_1")
	assert_eq(after, before, "mismatched item_id should not apply additional marks")

