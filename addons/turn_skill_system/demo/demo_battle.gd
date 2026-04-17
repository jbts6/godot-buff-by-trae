extends Node

const SkillRuntime := preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid := preload("res://addons/turn_skill_system/runtime/grid.gd")
const DemoUnit := preload("res://addons/turn_skill_system/demo/demo_unit.gd")
const EventNames := preload("res://addons/turn_skill_system/runtime/event_names.gd")

func _ready() -> void:
	# 1) 加载 OmniBuff 数据集（与 rpg_tests 对齐）
	var result := OmniBuff.ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var enums_rt := OmniBuff.EnumsRuntime.from_enums_json(result.enums)
	var ds := OmniBuff.DatasetCompiler.compile(result.manifest, enums_rt, result.sources)

	# 2) 构造单位（2~4 个）
	var a_stats := OmniBuff.StatsComponent.new(1001, ds)
	var e1_stats := OmniBuff.StatsComponent.new(2001, ds)
	var e2_stats := OmniBuff.StatsComponent.new(2002, ds)

	var a_buffs := OmniBuff.BuffCore.new(ds, enums_rt)
	var e1_buffs := OmniBuff.BuffCore.new(ds, enums_rt)
	var e2_buffs := OmniBuff.BuffCore.new(ds, enums_rt)

	var ally := DemoUnit.new(1001, "ally", Vector2i(2, 1), a_stats, a_buffs)
	var enemy1 := DemoUnit.new(2001, "enemy", Vector2i(0, 1), e1_stats, e1_buffs)
	var enemy2 := DemoUnit.new(2002, "enemy", Vector2i(1, 1), e2_stats, e2_buffs)

	var grid := Grid.new()
	grid.set_units([ally, enemy1, enemy2])

	var runtime_dict := {
		"stats_by_entity": {1001: a_stats, 2001: e1_stats, 2002: e2_stats},
		"buff_by_entity": {1001: a_buffs, 2001: e1_buffs, 2002: e2_buffs},
	}

	# 3) 绑定到 Autoload（若插件启用）
	var rt = null
	if has_node("/root/TurnSkillRuntime"):
		rt = get_node("/root/TurnSkillRuntime")
		rt.ensure_ready()
		rt.grid = grid
		rt.omnibuff.setup(ds, enums_rt, runtime_dict)
		# passive/aura 需要提前注册
		rt.passive_manager.register_unit_passives(ally, ["pas_demo_turn_start_buff"])
		rt.aura_manager.register_aura(ally, "aur_demo_front_row_atk")
		rt.aura_manager.refresh_all()

	# 4) 触发回合开始事件（演示被动）
	if rt != null:
		rt.event_bus.emit_event(EventNames.TURN_STARTED, {"turn_index": 1})
		rt.aura_manager.refresh_all()

	# 5) 主动：单体（FIRST）
	var r1 := SkillRuntime.cast("act_demo_single", ally, null, {
		"grid": grid,
		"dataset": ds,
		"enums_rt": enums_rt,
		"runtime_dict": runtime_dict,
		"turn_index": 1,
	})
	print("[demo] act_demo_single => ", r1)

	# 6) 主动：十字（以 enemy2 的格为中心）
	var r2 := SkillRuntime.cast_to_cell("act_demo_cross", ally, enemy2.cell, {
		"grid": grid,
		"dataset": ds,
		"enums_rt": enums_rt,
		"runtime_dict": runtime_dict,
		"turn_index": 1,
	})
	print("[demo] act_demo_cross => ", r2)
