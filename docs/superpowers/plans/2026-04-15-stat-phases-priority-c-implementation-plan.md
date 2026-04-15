# Stat Phases/Priority (C Minimal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 C-最小集：为属性系统增加 `priority` 稳定排序、`OVERRIDE/FINAL`、最终 `CLAMP(min/max)`，并用专门 GUT 单测锁死行为（没单测不算完成）。

**Architecture:** TDD：先在 `data/rpg_tests` 加入 C 专用 buff fixtures（override/final_add/clamp），再新增 2 个 GUT 测试文件（override 冲突 + clamp），使其在当前实现下失败；随后修改 `BuffCore._rebuild_instance_modifiers` 注入 `priority` 并允许 OVERRIDE/FINAL + ADD/FINAL；最后在 `StatsCore.recompute` 实现 phase 管线：FLAT → PERCENT → FINAL(override winner + final add) → CLAMP，并确保全量测试通过。

**Tech Stack:** Godot 4.7 + GDScript + GUT + data/rpg_tests。

---

## 0) 文件清单

**数据：**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_stat_priority_and_override.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_stat_clamp.gd`

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`

---

## Task 1：补齐 rpg_tests 的 C 专用 buff fixtures

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 添加 OVERRIDE/FINAL（不同 priority）**

```json
{
  "id": "buff_c_override_hit_0_p900",
  "name": "C测试：HIT_RATE=0（OVERRIDE/FINAL p900）",
  "buff_type": "EXPLICIT",
  "tags": ["DEBUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "HIT_RATE", "op": "OVERRIDE", "phase": "FINAL", "priority": 900, "value": 0.0 }
  ],
  "triggers": []
}
```

```json
{
  "id": "buff_c_override_hit_1_p800",
  "name": "C测试：HIT_RATE=1（OVERRIDE/FINAL p800）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "HIT_RATE", "op": "OVERRIDE", "phase": "FINAL", "priority": 800, "value": 1.0 }
  ],
  "triggers": []
}
```

- [ ] **Step 2: 添加 OVERRIDE/FINAL（同 priority，用于“后施加”胜）**

```json
{
  "id": "buff_c_override_hit_0_p850",
  "name": "C测试：HIT_RATE=0（OVERRIDE/FINAL p850）",
  "buff_type": "EXPLICIT",
  "tags": ["DEBUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "HIT_RATE", "op": "OVERRIDE", "phase": "FINAL", "priority": 850, "value": 0.0 }
  ],
  "triggers": []
}
```

```json
{
  "id": "buff_c_override_hit_1_p850",
  "name": "C测试：HIT_RATE=1（OVERRIDE/FINAL p850）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "HIT_RATE", "op": "OVERRIDE", "phase": "FINAL", "priority": 850, "value": 1.0 }
  ],
  "triggers": []
}
```

- [ ] **Step 3: 添加 ADD/FINAL（可选但用于锁死阶段顺序）**

```json
{
  "id": "buff_c_final_add_hit_plus_0_2",
  "name": "C测试：HIT_RATE 最终+0.2（ADD/FINAL）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "HIT_RATE", "op": "ADD", "phase": "FINAL", "priority": 950, "value": 0.2 }
  ],
  "triggers": []
}
```

- [ ] **Step 4: 添加 clamp 测试 buff（把 HIT_RATE 加到 >1）**

```json
{
  "id": "buff_c_add_hit_plus_2",
  "name": "C测试：HIT_RATE +2（ADD/FLAT）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "HIT_RATE", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 2.0 }
  ],
  "triggers": []
}
```

- [ ] **Step 5: 提交**

```bash
git -C godot-buff add data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "test(data): add C stat phase/priority fixtures"
```

---

## Task 2：新增单测：priority + OVERRIDE/FINAL（含 tie-break）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_stat_priority_and_override.gd`

- [ ] **Step 1: 写 failing tests**

```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_override_wins_by_higher_priority() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7701, ds, enums_rt)

	var hit_id := ds.stat_id("HIT_RATE")

	e.buffs.apply_buff(e.stats, "buff_c_override_hit_1_p800", 1)
	e.buffs.apply_buff(e.stats, "buff_c_override_hit_0_p900", 1)
	assert_eq(float(e.stats.get_final(hit_id)), 0.0)

func test_override_tie_breaker_last_applied_wins() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7702, ds, enums_rt)

	var hit_id := ds.stat_id("HIT_RATE")

	# 同 priority：先 0 再 1 => 1 应胜（后施加覆盖先施加）
	e.buffs.apply_buff(e.stats, "buff_c_override_hit_0_p850", 1)
	e.buffs.apply_buff(e.stats, "buff_c_override_hit_1_p850", 1)
	assert_eq(float(e.stats.get_final(hit_id)), 1.0)
```

- [ ] **Step 2: 提交 failing tests**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_stat_priority_and_override.gd
git -C godot-buff commit -m "test(c): add override/priority tests"
```

---

## Task 3：新增单测：CLAMP（min/max）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_stat_clamp.gd`

- [ ] **Step 1: 写 failing test：HIT_RATE clamp 到 1**

```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_hit_rate_is_clamped_to_max_1() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7710, ds, enums_rt)

	var hit_id := ds.stat_id("HIT_RATE")
	e.buffs.apply_buff(e.stats, "buff_c_add_hit_plus_2", 1)
	assert_eq(float(e.stats.get_final(hit_id)), 1.0)
```

- [ ] **Step 2: 提交 failing test**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_stat_clamp.gd
git -C godot-buff commit -m "test(c): add clamp tests"
```

---

## Task 4：运行时实现（BuffCore 注入 priority + StatsCore phase 管线）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`

- [ ] **Step 1: OmniModifierRef 增加 priority 字段**

在 `buff_core.gd`：
```gdscript
class OmniModifierRef:
	var priority: int = 0
```

- [ ] **Step 2: _rebuild_instance_modifiers 写入 priority，并支持 ADD/FINAL + OVERRIDE/FINAL**

在 `buff_core.gd` 中替换 supported 判断：
```gdscript
var supported := (op == "ADD" and (phase == "FLAT" or phase == "FINAL")) \
	or (op == "MUL" and phase == "PERCENT") \
	or (op == "OVERRIDE" and phase == "FINAL")
```

并写入：
```gdscript
mr.priority = int(e.get("priority", 0))
```

ADD/FINAL：`mr.value` 直接记录，`mr.add_value` 只在 ADD/FLAT 时使用（保持兼容字段语义）。

- [ ] **Step 3: StatsCore.recompute 实现 phase：FLAT→PERCENT→FINAL(override winner + final_add)→CLAMP**

在 `stats_core.gd` 的 `recompute(stat_id)` 改为：
```gdscript
var base := base_values[stat_id]
var flat := 0.0
var pct := 0.0
var final_add := 0.0
var has_override := false
var override_v := 0.0
var override_pri := -2147483648
var override_src := -2147483648

for m in modifiers_by_stat[stat_id]:
	if m == null or typeof(m) != TYPE_OBJECT:
		continue
	var op := String(m.op)
	var ph := String(m.phase)
	var val := float(m.value)
	var pri := int(m.priority)
	var src := int(m.source_inst_id)
	if op == "ADD" and ph == "FLAT":
		flat += val
	elif op == "MUL" and ph == "PERCENT":
		pct += val
	elif op == "ADD" and ph == "FINAL":
		final_add += val
	elif op == "OVERRIDE" and ph == "FINAL":
		if (not has_override) or (pri > override_pri) or (pri == override_pri and src > override_src):
			has_override = true
			override_pri = pri
			override_src = src
			override_v = val

var v := (base + flat) * (1.0 + pct)
if has_override:
	v = override_v
v += final_add

var def: Dictionary = ds.stat_defs[stat_id]
if bool(def.get("clamp", false)):
	v = clamp(v, float(def.get("min", v)), float(def.get("max", v)))
final_values[stat_id] = v
```

- [ ] **Step 4: 跑全量 GUT tests**

- [ ] **Step 5: 提交运行时实现**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd addons/omnibuff/runtime/core/stats_core.gd
git -C godot-buff commit -m "feat(c): add priority/override/final and stat clamp"
```

---

## Self-Review

- [ ] 搜索计划与代码无 TODO/TBD
- [ ] override 冲突策略符合方案 A（priority 最大；同 priority 后施加胜）
- [ ] clamp 只依赖 stat_defs.clamp/min/max（集中约束）
- [ ] 新增 2 个 C 单测文件全绿

