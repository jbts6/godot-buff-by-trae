extends GutTest

## 目标：验证 DOT 的 max_stack 作为“目标总上限（跨来源共享）”时的裁剪语义
## 设定：
## - Fire DOT：buff_dot_fire_cap4_3t，max_stack=4，ownership=BY_SOURCE_INSTANCE，stack.mode=ADD_STACK
## 预期：
## - A 对目标施加 +2（两次 apply）=> A 实例 stacks=2
## - B 对目标施加 +3（三次 apply）=> 因总上限=4，B 实例应被裁剪到 stacks=2
## - 满层后 B 再次 apply：stacks 不变，但仍刷新 remaining_turns（RESET_TO_MAX）

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const TurnComponent := preload("res://addons/omnibuff/runtime/components/turn_component.gd")
const DamagePipeline := preload("res://addons/omnibuff/runtime/core/damage_pipeline.gd")
const Replay := preload("res://addons/omnibuff/runtime/core/replay.gd")


func _find_inst(buffs: OmniBuffCore, ds: OmniCompiledDataset, buff_id_str: String, source_eid: int) -> Variant:
	var bdid := int(ds.buff_id(buff_id_str))
	assert_true(bdid >= 0, "unknown buff_id=%s" % [buff_id_str])
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		if int(inst.buff_def_id) == bdid and int(inst.source_entity_id) == source_eid:
			return inst
	return null


func test_dot_max_stack_is_shared_across_sources_and_refreshes_on_full() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var src_a := TestBattle.make_entity(8101, ds, enums_rt)
	var src_b := TestBattle.make_entity(8102, ds, enums_rt)
	var tgt := TestBattle.make_entity(8103, ds, enums_rt)

	# A: +2 stacks（两次 apply）
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_cap4_3t", int(src_a.stats.entity_id))
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_cap4_3t", int(src_a.stats.entity_id))

	# B: +3 stacks（三次 apply）=> 因总上限=4，B 最终应只有 2 stacks
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_cap4_3t", int(src_b.stats.entity_id))
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_cap4_3t", int(src_b.stats.entity_id))
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_cap4_3t", int(src_b.stats.entity_id))

	assert_eq(tgt.buffs.inst_ids.size(), 2, "should have 2 instances (A and B)")
	var inst_a = _find_inst(tgt.buffs, ds, "buff_dot_fire_cap4_3t", int(src_a.stats.entity_id))
	var inst_b = _find_inst(tgt.buffs, ds, "buff_dot_fire_cap4_3t", int(src_b.stats.entity_id))
	assert_not_null(inst_a)
	assert_not_null(inst_b)
	assert_eq(int(inst_a.stacks), 2)
	assert_eq(int(inst_b.stacks), 2, "B should be clipped by shared max_stack=4")

	# 让回合推进一次，remaining_turns 应 -1（从 3 到 2）
	var turn := TurnComponent.new()
	var pipe := DamagePipeline.new()
	var replay := Replay.new()
	var runtime := TestBattle.make_runtime([src_a, src_b, tgt])
	var ids := PackedInt32Array([8101, 8102, 8103]); ids.sort()
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

	inst_b = _find_inst(tgt.buffs, ds, "buff_dot_fire_cap4_3t", int(src_b.stats.entity_id))
	assert_not_null(inst_b)
	assert_true(int(inst_b.remaining_turns) <= 2, "after turn end, remaining_turns should decrease")

	# 满层再 apply（B）：stacks 不变，但 remaining_turns 刷新回 3（RESET_TO_MAX）
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_cap4_3t", int(src_b.stats.entity_id))
	inst_b = _find_inst(tgt.buffs, ds, "buff_dot_fire_cap4_3t", int(src_b.stats.entity_id))
	assert_eq(int(inst_b.stacks), 2)
	assert_eq(int(inst_b.remaining_turns), 3, "full-stack apply should still refresh duration")

