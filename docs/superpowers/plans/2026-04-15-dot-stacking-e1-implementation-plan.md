# DOT Stacking (E1: Merge-by-Source + Aggregate-by-Tags) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 E1：DOT 按来源合并（同 target+buff_id+source 仅 1 条 DotInstance），同一来源重复施加时 `remaining_turns=turns` 且按 `stack.mode` 叠层；每次 tick 时对同 target+tick_phase+tags_mask 的 DOT 伤害聚合成“一段伤害”，不同 tags_mask 分段结算。全程用 GUT 单测锁死。

**Architecture:** 先补 rpg_tests fixtures（新增 POISON DOT 与可叠层 DOT），再新增 2-3 个 GUT 测试（多来源实例数、聚合为一段、跨 tags_mask 分段、同源叠层+刷新 turns），保证在当前实现下失败；随后修改 `BuffCore.apply_buff` 的 DOT 创建逻辑（按来源合并复用 DotInstance），并修改 `_tick_dots`（先逐 DOT 计算 base_damage，再按 tags_mask 分组汇总，调用一次 `deal_damage_with_tags` 结算）。最后全量回归。

**Tech Stack:** Godot 4.7 + GDScript + GUT + rpg_tests。

---

## 0) 文件清单

**数据：**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dot_merge_by_source_and_aggregate.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dot_aggregate_separates_by_tags_mask.gd`
- (可选) Create: `godot-buff/addons/omnibuff/tests/rpg/test_dot_merge_by_source_refresh_and_stack.gd`

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/replay.gd`（如需新增聚合 trace；否则不改）

---

## Task 1：补齐 rpg_tests DOT fixtures（FIRE/POISON + 可叠层）

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 新增 POISON DOT（tags_mask 不同）**

追加：
```json
{
  "id": "buff_dot_poison_3t",
  "name": "测试：中毒DOT（3回合/回合开始结算）",
  "buff_type": "EXPLICIT",
  "tags": ["DEBUFF", "DOT", "POISON"],
  "duration": { "type": "TURNS", "turns": 3, "tick_phase": "TURN_START" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "BY_SOURCE_INSTANCE" },
  "dot": { "tick_phase": "TURN_START", "element": "POISON", "base_ratio": 0.2, "read_source_stat": "ATK" },
  "effects": [],
  "triggers": []
}
```

- [ ] **Step 2: 新增可叠层 FIRE DOT（ADD_STACK）**

追加：
```json
{
  "id": "buff_dot_fire_stack_3t",
  "name": "测试：灼烧DOT可叠层（3回合/回合开始结算）",
  "buff_type": "EXPLICIT",
  "tags": ["DEBUFF", "DOT", "FIRE"],
  "duration": { "type": "TURNS", "turns": 3, "tick_phase": "TURN_START" },
  "stack": { "mode": "ADD_STACK", "max_stack": 3, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "BY_SOURCE_INSTANCE" },
  "dot": { "tick_phase": "TURN_START", "element": "FIRE", "base_ratio": 0.1, "read_source_stat": "ATK" },
  "effects": [],
  "triggers": []
}
```

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "test(data): add poison + stackable dot fixtures"
```

---

## Task 2：新增单测：按来源合并 + 同 tags_mask 聚合为一段伤害

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dot_merge_by_source_and_aggregate.gd`

- [ ] **Step 1: 写 failing test（FIRE DOT 两来源 -> DotInstance=2 但伤害只结算 1 段）**

说明：我们用 `Replay` 的 `damage_traces`（若已有）或通过 `HP` 变化验证“总伤害正确”，并借助一个新的最小 helper（在测试里）验证“伤害段数=1”。如果当前 replay 没有 damage trace，则本测试先只验证：  
1) dot_traces 是 2 条（每来源一条）  
2) HP 一次性减少为两来源和（通过 before/after HP）  
段数验证需要我们在实现侧补一个“tick 聚合 trace”（见 Task 4 可选）。

```gdscript
extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const TurnComponent := preload("res://addons/omnibuff/runtime/components/turn_component.gd")

func test_two_sources_fire_dot_aggregates_to_one_damage() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()
	var turn = TurnComponent.new()

	var src1 = TestBattle.make_entity(7901, ds, enums_rt)
	var src2 = TestBattle.make_entity(7902, ds, enums_rt)
	var tgt = TestBattle.make_entity(7903, ds, enums_rt)
	var runtime = TestBattle.make_runtime([src1, src2, tgt])

	# 让两个来源分别施加同一个 FIRE DOT（同 buff_id）
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", 7901)
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", 7902)
	assert_eq(int((tgt.buffs.dots_by_target[tgt.stats.entity_id] as Array).size()), 2)

	var hp_id := ds.stat_id("HP")
	var before_hp := float(tgt.stats.get_final(hp_id))
	var before_traces := replay.dot_traces.size()

	var ids := PackedInt32Array([7901, 7902, 7903]); ids.sort()
	turn.on_turn_start(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, replay)

	var after_hp := float(tgt.stats.get_final(hp_id))
	assert_eq(replay.dot_traces.size() - before_traces, 2) # 每来源一条 trace
	assert_true(after_hp < before_hp) # 总伤害发生
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_dot_merge_by_source_and_aggregate.gd
git -C godot-buff commit -m "test(e1): add dot merge-by-source + aggregate test"
```

---

## Task 3：新增单测：不同 tags_mask 必须分段结算（FIRE vs POISON）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dot_aggregate_separates_by_tags_mask.gd`

- [ ] **Step 1: 写 failing test（两元素 -> 结算应为两段；且同元素多来源仍聚合）**

最小实现：先验证 “dot_traces 分别按来源记录”，并验证 `HP` 总下降等于 FIRE聚合+POISON聚合 的和；  
若实现侧补“tick聚合段数 trace”，则断言段数为 2（FIRE一段 + POISON一段）。

```gdscript
extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const TurnComponent := preload("res://addons/omnibuff/runtime/components/turn_component.gd")

func test_fire_and_poison_do_not_aggregate_together() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()
	var turn = TurnComponent.new()

	var src1 = TestBattle.make_entity(7911, ds, enums_rt)
	var src2 = TestBattle.make_entity(7912, ds, enums_rt)
	var tgt = TestBattle.make_entity(7913, ds, enums_rt)
	var runtime = TestBattle.make_runtime([src1, src2, tgt])

	# FIRE 两来源
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", 7911)
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", 7912)
	# POISON 两来源
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_poison_3t", 7911)
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_poison_3t", 7912)

	var hp_id := ds.stat_id("HP")
	var before_hp := float(tgt.stats.get_final(hp_id))
	var before_traces := replay.dot_traces.size()

	var ids := PackedInt32Array([7911, 7912, 7913]); ids.sort()
	turn.on_turn_start(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, replay)

	assert_eq(replay.dot_traces.size() - before_traces, 4) # 4 条 dot_traces（每来源一条）
	assert_true(float(tgt.stats.get_final(hp_id)) < before_hp)
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_dot_aggregate_separates_by_tags_mask.gd
git -C godot-buff commit -m "test(e1): add tag-separated dot aggregation test"
```

---

## Task 4：运行时实现：按来源合并 + tick 聚合结算

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- (可选) Modify: `godot-buff/addons/omnibuff/runtime/core/replay.gd`

- [ ] **Step 1: DotInstance 增加 stacks 字段（默认1）**

在 `buff_core.gd` 的 `class DotInstance`：
```gdscript
var stacks: int = 1
```

- [ ] **Step 2: apply_buff 创建/合并 DotInstance（按来源合并）**

在 `apply_buff` 创建 DOT 的代码块处：
- 先在 `dots_by_target[target]` 查找是否已有同 `(buff_def_id, source_entity_id, tick_phase)` 的 DotInstance
  -（tick_phase 通常来自 dot.tick_phase，加入键能避免未来同 buff_id 不同 tick_phase 的歧义）
- 若存在：
  - `d.remaining_turns = turns`（重置）
  - 按 stack.mode 更新 `d.stacks`
  - `d.owner_buff_inst_id = inst_id`（更新归属，便于移除时清理）
- 若不存在：创建新 DotInstance，`stacks=1`

- [ ] **Step 3: _tick_dots：逐 DOT 计算 base_damage，再按 tags_mask 聚合后结算**

把原先 “每 DotInstance 调一次 deal_damage_with_tags” 改为：
1) 遍历 dots（同 tick_phase），对每个 DotInstance：
   - 读取来源属性 `src_v`
   - `base_damage_i = src_v * base_ratio * stacks`
   - 用 `tags_mask` 作为分组 key，累计 `sum_damage_by_tags[tags_mask] += base_damage_i`
   - 仍记录每来源的 dot_trace（保持 debug 能力）
   - `remaining_turns -= 1` / 到期丢弃
2) 遍历 `sum_damage_by_tags`：
   - 对每个 tags_mask 调用一次：
     - `pipeline.deal_damage_with_tags(source_stats=?, target_stats, ..., base_damage_sum, tags_mask, ...)`
   - 注意：此处 `source_stats/source_buff` 不再唯一。最小实现建议：
     - 传入 `target_stats` 的 BuffCore 作为 target_buff 不变
     - 对 source_stats/source_buff：取任意一个来源（例如最后一个贡献者），因为 tags_mask 结算的伤害已经是“汇总 base_damage”，后续 pipeline 如再读来源属性会重复；因此 **必须确保 pipeline 只使用 base_damage**，不再读取 source stats（当前实现就是如此）。

> 若你希望在 DamageTrace 中保留“聚合段的来源列表”，则需要扩展 replay（非本轮必须）。

- [ ] **Step 4: （可选）在 replay 增加 tick 聚合段 trace，便于单测断言“段数=1/2”**

新增：
```gdscript
func trace_dot_aggregate(turn_index: int, target_entity_id: int, tick_phase: String, tags_mask: int, base_damage_sum: float) -> void
```

- [ ] **Step 5: 全量 GUT**

- [ ] **Step 6: 提交运行时实现**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff add addons/omnibuff/runtime/core/replay.gd  # 若改了
git -C godot-buff commit -m "feat(e1): merge dots by source and aggregate tick damage by tags"
```

---

## Self-Review

- [ ] 多来源 FIRE：DotInstance=2，dot_traces=2，但伤害对目标结算为 1 段（若有 aggregate trace 则段数=1）
- [ ] FIRE+POISON：同元素内聚合，不同 tags_mask 分段（段数=2）
- [ ] 同源重复施加（ADD_STACK）：实例数不增长、turns 重置、伤害随 stacks 增大
- [ ] 现有 `test_dot_multi_source_trace.gd` 仍通过

