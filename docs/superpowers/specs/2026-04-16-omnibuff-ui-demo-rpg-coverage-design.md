# OmniBuff UI Demo 覆盖 RPG Tests 设计

## 背景

目前 `addons/omnibuff/demo/demo_runner.gd` 偏向“控制台打印”，且长期未覆盖 `addons/omnibuff/tests/rpg/` 中的大量能力点。虽然已新增 `addons/omnibuff/demo/buff_ui_demo.tscn`，但其逻辑仍主要复刻 `demo_runner.gd`，对 rpg tests 覆盖不足。

## 目标

升级 `buff_ui_demo`，让它以可视化方式**覆盖并演示 `tests/rpg` 中的已实现能力**，并明确展示“调用位置/顺序/预期现象”。要求：

1) UI 可直接打开运行（不依赖测试框架）
2) 支持选择数据集：`base_demo` 与 `rpg_tests`
3) 以“场景（scenario）”为单位组织 demo，一键运行并输出：
   - 关键数值（ATK/DEF/HP/SHIELD/stack）
   - Buff 实例列表
   - Replay（damage_traces / dot_traces）摘要与 debug dump
4) 所有 scenario 都是幂等的：运行前会 reset 状态（避免污染下一次）

## 非目标

- 不把每一个 `test_*.gd` 逐字搬到 UI（否则 UI 会爆炸）
- 不要求 demo 具备严格断言（但建议提供“轻量 PASS/FAIL 自检”）
- 不引入新的 gameplay 系统（只演示已有实现）

---

## UI 结构设计（推荐）

在现有 `buff_ui_demo.tscn` 基础上重构为“左侧场景列表 + 右侧输出”：

- 顶部：Dataset 选择（OptionButton：base_demo / rpg_tests）、Load、Reset
- 左侧：Scenario 列表（ItemList）
- 右侧：输出区（RichTextLabel，带清空按钮）
- 底部：Run Selected / Run All（可选）

> 这样比“堆很多按钮”更可扩展，也能把 `tests/rpg` 的覆盖面做得很广而不牺牲可用性。

---

## Scenario 设计（覆盖矩阵）

每个 scenario 对应一组 tests 主题（不是单个文件一一映射），并在日志中写明“覆盖哪些 test”。

### A. 数据集 / 校验 / Manifest

- **Dataset: authority & isolation（展示 issues 输出）**
  - 覆盖：`test_manifest_loader_authority.gd`、`test_dataset_isolation_manifests.gd`
  - UI 行为：加载 `rpg_tests/manifest.json`，打印 validate issues（若有）与文件列表

### B. Buff 生命周期（A1~A4）

- **Lifecycle: expire**
  - 覆盖：`test_buff_lifecycle_expire.gd`
  - 行为：施加 3 回合 buff，推进 turn，观察 remaining_turns 与移除时机

- **Lifecycle: refresh_policy**
  - 覆盖：`test_buff_lifecycle_refresh_policy.gd`

- **Lifecycle: stacking (REPLACE / ADD_STACK / MULTI_INSTANCE)**
  - 覆盖：`test_buff_lifecycle_stacking.gd`

- **Lifecycle: while-condition**
  - 覆盖：`test_buff_lifecycle_while_condition.gd`

### C. 主动移除 / 驱散（A5 / M7）

- **Remove: by_buff_id/by_tag/by_source**
  - 覆盖：`test_buff_removal_a5.gd`

- **Dispel: by_tag/by_source/by_type**
  - 覆盖：`test_dispel_by_tag.gd`、`test_dispel_by_source.gd`、`test_dispel_by_type.gd`

- **Undispellable + dispel immunity**
  - 覆盖：`test_undispellable_and_immunity.gd`

### D. 伤害流水线 / 防御 / 护盾

- **Shield absorb**
  - 覆盖：`test_shield_absorb.gd`

- **Damage reduction**
  - 覆盖：`test_damage_reduction.gd`

- **Stage traces present**
  - 覆盖：`test_damage_pipeline_stage_traces_present.gd`

### E. 事件动作（EventIndex）

- **ADD_BASE_DAMAGE**
  - 覆盖：`test_event_add_base_damage.gd`

- **CHANCE_APPLY_BUFF determinism（含 roll_key 展示）**
  - 覆盖：`test_event_chance_apply_buff_determinism.gd`、`test_hit_crit_determinism.gd`、`test_hit_and_crit_deterministic.gd`、`test_roll_key_makes_hit_crit_independent_per_strike.gd`

- **Shatter shield before apply**
  - 覆盖：`test_event_shatter_shield_before_apply.gd`

### F. DOT（实例、过滤、聚合、追帧）

- **DOT actions: filter by tags**
  - 覆盖：`test_dot_actions_filter_by_tags.gd`

- **DOT actions: mul/add/set/clear**
  - 覆盖：`test_dot_actions_mul_add_set_clear.gd`

- **DOT aggregate: separates by tags mask**
  - 覆盖：`test_dot_aggregate_separates_by_tags_mask.gd`

- **DOT merge: by source and aggregate**
  - 覆盖：`test_dot_merge_by_source_and_aggregate.gd`

- **No leak buff & dot counts**
  - 覆盖：`test_no_leak_buff_and_dot_counts.gd`

### G. 多段 / AOE / 回放

- **Multi-hit: each hit applies DOT**
  - 覆盖：`test_multihit_each_hit_applies_dot.gd`

- **AOE multi-target + multi-hit + per-target hit/crit + DOT**
  - 覆盖：`test_aoe_multitarget_multihit_per_target_hit_crit_and_dot.gd`

- **Replay fields + debug dump range**
  - 覆盖：`test_replay_damage_trace_fields.gd`、`test_replay_dot_trace_fields.gd`、`test_replay_debug_dump_range.gd`

### H. Stat 计算

- **Percent layers（分段乘法）**
  - 覆盖：`test_percent_modifier.gd`、`test_stat_percent_layers.gd`

- **Priority & override**
  - 覆盖：`test_stat_priority_and_override.gd`

- **Clamp**
  - 覆盖：`test_stat_clamp.gd`

### I. 整回合脚本（集成）

- **Full turn script battle**
  - 覆盖：`test_full_turn_script_battle.gd`

---

## 运行时组织方式（代码结构）

在 `buff_ui_demo.gd` 内引入 `Scenario` 结构（Dictionary 即可）：

```gdscript
var scenarios: Array = [
  {"id":"lifecycle_expire", "title":"Lifecycle / Expire", "dataset":"rpg_tests", "fn": Callable(self, "_sc_lifecycle_expire"), "covers":[...]}
]
```

入口：
- `load_dataset(dataset_id)`：加载并编译对应 manifest
- `run_scenario(s)`：reset → load_dataset_if_needed → 执行 fn → 输出 summary

建议新增一套小工具函数：
- `_mk_entity(eid)`：创建 StatsComponent + BuffCore
- `_mk_runtime(map)`：生成 runtime dict
- `_dump_entity(label, stats, buffs)`：打印 stats + buff instances
- `_dump_replay(from_damage, from_dot)`：打印 replay 增量

---

## 验收标准

1) `buff_ui_demo` 能切换 `rpg_tests` 数据集并运行上述 scenario（至少每个大类 1 个）
2) 每个 scenario 的日志清楚标注覆盖哪些 tests，并展示关键现象
3) 不破坏现有 `demo_scene.tscn` / `demo_runner.gd`

