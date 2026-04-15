# DamagePipeline (F Minimal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 以最小改动把 F（DamagePipeline）收尾到可打勾：新增 1 个专门 GUT 用例锁死 F1 阶段骨架/追帧契约，并同步更新 checklist 将 F1~F5 标为完成。

**Architecture:** 不改运行时语义（现有 F2~F5 已有单测覆盖）；只新增 `test_damage_pipeline_stage_traces_present.gd` 做 F1 追帧契约测试，然后更新 `omnibuff-done-definition.md` 勾选 F 项。

**Tech Stack:** Godot 4.7 + GDScript + GUT。

---

## 0) 文件清单

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_damage_pipeline_stage_traces_present.gd`

**文档：**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

---

## Task 1：新增 F1 专门测试（阶段骨架 + 追帧契约）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_damage_pipeline_stage_traces_present.gd`

- [ ] **Step 1: 写测试**

```gdscript
extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_damage_trace_contains_all_pipeline_stage_keys() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	var attacker_id := 8201
	var defender_id := 8202
	var a := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var d := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([a, d])

	# 固定命中/暴击，避免随机性导致的“没有 after 阶段副作用”误读
	a.stats.add_base(ds.stat_id("HIT_RATE"), 1.0 - float(a.stats.get_final(ds.stat_id("HIT_RATE"))))
	a.stats.add_base(ds.stat_id("CRIT_RATE"), 0.0 - float(a.stats.get_final(ds.stat_id("CRIT_RATE"))))
	d.stats.add_base(ds.stat_id("EVADE"), 0.0 - float(d.stats.get_final(ds.stat_id("EVADE"))))

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 10.0, replay, 1, tags_mask, runtime)

	assert_eq(replay.damage_traces.size(), 1)
	var t = replay.damage_traces[0]
	assert_true(typeof(t.stage_triggers) == TYPE_DICTIONARY)

	var keys := ["BUILD","BEFORE_DEAL","BEFORE_TAKE","APPLY_ATK","APPLY_DEF","AFTER_DEAL","AFTER_TAKE"]
	for k in keys:
		assert_true(t.stage_triggers.has(k), "missing stage key: %s" % k)
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_damage_pipeline_stage_traces_present.gd
git -C godot-buff commit -m "test(f1): lock damage pipeline stage trace contract"
```

---

## Task 2：更新 checklist 勾选 F1~F5

**Files:**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

- [ ] **Step 1: 勾选 F**

将以下条目标为完成：
- F1~F5 全部勾选为 `[x]`

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add docs/superpowers/checklists/omnibuff-done-definition.md
git -C godot-buff commit -m "docs(checklist): mark F complete"
```

