# Performance + Engineering (J1~J3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收尾 J（性能预算与工程化）：补 J1 性能预算文档、补 J3 生命周期回归测试、在关键代码处补“禁止全量遍历”注释（J2 最小守门），并同步更新 checklist 勾选 J1~J3。

**Architecture:** 先写文档与测试（不改语义），测试通过后再做少量注释增强，最后更新 checklist。

**Tech Stack:** Godot 4.7 + GDScript + GUT + Markdown。

---

## 0) 文件清单

**文档：**
- Create: `godot-buff/docs/superpowers/perf/omnibuff-performance-budget.md`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_no_leak_buff_and_dot_counts.gd`

**注释增强（J2）：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- (可选) Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`

**checklist：**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

---

## Task 1：新增 J1 性能预算文档

**Files:**
- Create: `godot-buff/docs/superpowers/perf/omnibuff-performance-budget.md`

- [ ] **Step 1: 写文档（直接粘贴以下内容并按需微调）**

```md
# OmniBuff 性能预算（J）

## 规模符号
- N_entities：战斗实体数
- N_inst：单实体 buff 实例数（BuffCore.inst_ids.size）
- N_listeners：单实体 listeners 总数（EventIndex 各 key 列表长度之和）
- N_dot：单实体 DOT 实例数（BuffCore.dots_by_target[entity].size）

## 关键操作复杂度（上界）

### apply_buff（施加）
- ownership lookup：O(1)
- modifiers 注册/聚合：O(k_mod)
- listeners 注册：O(k_trg)
- DOT upsert（按来源合并）：O(N_dot)

### remove_by_instance（移除）
- modifiers 撤销：O(k_mod)
- listeners 注销：O(k_trg)
- 清理 DOT（owner_buff_inst_id 匹配过滤）：O(N_dot)
- inst_ids 重建：O(N_inst)

### emit_event（事件触发）
- 仅遍历 listeners 子集：O(N_listeners_for_key)
- action 成本：与 action 类型相关（APPLY_BUFF/CHANCE/ADD_BASE_DAMAGE/DOT_*）

### deal_damage（单次伤害）
- 固定阶段流程 + emit_event 的成本

### tick_dots（每回合 DOT 结算）
- 遍历目标 DOT：O(N_dot)
- 按 tags_mask 分组聚合：O(N_dot)

## 建议上限（保守值）
- N_entities <= 64
- N_inst <= 1000 / entity
- N_dot <= 200 / entity
- N_listeners_for_key <= 2000（超过建议收紧 filters，否则性能与可控性风险上升）

## 禁止点（J2）
- 禁止在 deal_damage/emit_event/tick_dots 内遍历全实体（buff_by_entity.keys/stats_by_entity.keys）
- 禁止在 tick_dots 内遍历所有 target（必须按当前 target）
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add docs/superpowers/perf/omnibuff-performance-budget.md
git -C godot-buff commit -m "docs(j1): add omnibuff performance budget"
```

---

## Task 2：新增 J3 生命周期回归测试（回合推进 + 驱散不泄漏）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_no_leak_buff_and_dot_counts.gd`

- [ ] **Step 1: 写 failing test**

```gdscript
extends GutTest

const ReplayScript = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const TurnComponent = preload("res://addons/omnibuff/runtime/components/turn_component.gd")

func test_repeated_turns_and_dispels_do_not_leak_instances_or_dots() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()
	var turn = TurnComponent.new()

	var attacker_id: int = 9401
	var defender_id: int = 9402
	var attacker = TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender = TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime = TestBattle.make_runtime([attacker, defender])

	# 固定命中/暴击
	attacker.stats.add_base(ds.stat_id("HIT_RATE"), 1.0 - float(attacker.stats.get_final(ds.stat_id("HIT_RATE"))))
	attacker.stats.add_base(ds.stat_id("CRIT_RATE"), 0.0 - float(attacker.stats.get_final(ds.stat_id("CRIT_RATE"))))
	defender.stats.add_base(ds.stat_id("EVADE"), 0.0 - float(defender.stats.get_final(ds.stat_id("EVADE"))))

	# 命中后挂 DOT（会产生 buff 实例 + dot）
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_apply_dot", attacker_id)
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var ids := PackedInt32Array([attacker_id, defender_id]); ids.sort()

	var loop_count: int = 8
	for n in range(loop_count):
		# 三连（产生多个 DOT buff 实例，但按来源合并为 1 个 DotInstance）
		pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 12.0, replay, 1000 + n*3 + 0, tags_mask, runtime)
		pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 14.0, replay, 1000 + n*3 + 1, tags_mask, runtime)
		pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 18.0, replay, 1000 + n*3 + 2, tags_mask, runtime)

		# 推进到下一回合并结算（触发 DOT tick）
		turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
		turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

		# 驱散 DEBUFF（清 buff 实例 + dot）
		defender.buffs.dispel_by_tag(defender.stats, "DEBUFF", false)

		# 断言：驱散后 DOT 不应残留
		var dots_any = defender.buffs.dots_by_target.get(defender_id, null)
		if dots_any != null:
			assert_eq((dots_any as Array).size(), 0)
		assert_eq(defender.buffs.inst_ids.size(), 0)
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_no_leak_buff_and_dot_counts.gd
git -C godot-buff commit -m "test(j3): add no-leak regression for buffs and dots"
```

---

## Task 3：J2 注释增强（禁止全量遍历）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- (可选) Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`

- [ ] **Step 1: 在关键函数顶部补充复杂度/禁止点注释**

例如在：
- `emit_event`
- `_tick_dots`
- `deal_damage`

补充类似：
```gdscript
## PERF(J2):
## - 禁止遍历全实体（buff_by_entity/stats_by_entity keys）
## - 只允许遍历 listeners 子集 / 当前 target 的 DOT 列表
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd addons/omnibuff/runtime/core/damage_pipeline.gd
git -C godot-buff commit -m "docs(j2): annotate perf constraints in hot paths"
```

---

## Task 4：更新 checklist 勾选 J1~J3

**Files:**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

- [ ] **Step 1: 勾选 J1~J3 为 [x]**
- [ ] **Step 2: 提交**

```bash
git -C godot-buff add docs/superpowers/checklists/omnibuff-done-definition.md
git -C godot-buff commit -m "docs(checklist): mark J complete"
```

