# Event Filters/Actions (D Minimal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 扩展事件系统的 filters/actions，使其能用数据驱动实现“命中后碎盾（先碎盾再结算本次伤害）”，并用 GUT 单测锁死行为。

**Architecture:** 在现有 `EventIndex + BuffCore.emit_event` 框架上补最小通用能力：filters 增加 `require_hit` 与 `stat_threshold`，action 增加 `SET_STAT_FINAL`（通过调 base 实现 set final，不触碰 modifiers 细节）；碎盾挂在 `DAMAGE/APPLY` 阶段，保证发生在护盾吸收前。按 TDD：先加 rpg_tests fixtures + failing test，再实现校验/enums/runtime，最后全量回归。

**Tech Stack:** Godot 4.7 + GDScript + GUT。

---

## 0) 文件清单

**数据：**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`
- Modify: `godot-buff/data/base_demo/enums.json`（rpg_tests 复用该 enums）

**编译校验：**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`（允许新增 filter 字段；action_kind 枚举更新后会自动通过）

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`（Listener 增字段）
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`（注册/过滤/执行 action）

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_shatter_shield_before_apply.gd`

---

## Task 1：补齐 enums + validators（让 strict 校验通过）

**Files:**
- Modify: `godot-buff/data/base_demo/enums.json`
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

- [ ] **Step 1: enums.json 增加 action_kind**

在 `enums.action_kind` 末尾追加：
```json
"SET_STAT_FINAL"
```

- [ ] **Step 2: validators 允许新增 filters 字段**

在 `validators.gd` 中找到：
```gdscript
var allowed_filters := {"tag_mask_any": true, "damage_type_any": true, "skill_id": true}
```
改为：
```gdscript
var allowed_filters := {
  "tag_mask_any": true,
  "damage_type_any": true,
  "skill_id": true,
  "require_hit": true,
  "stat_threshold": true
}
```

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add data/base_demo/enums.json addons/omnibuff/config/compiler/validators.gd
git -C godot-buff commit -m "feat(d): allow new event filters and action kind"
```

---

## Task 2：补齐 rpg_tests fixtures（碎盾 buff）

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 新增 buff_on_hit_shatter_shield**

把以下 buff 追加到 `buffs[]`：
```json
{
  "id": "buff_on_hit_shatter_shield",
  "name": "命中后碎盾（APPLY前置）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [],
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "APPLY",
      "scope": "TARGET",
      "filters": {
        "tag_mask_any": ["BUFF"],
        "require_hit": true,
        "stat_threshold": { "scope": "TARGET", "stat": "SHIELD", "op": "GT", "value": 0.0 }
      },
      "action": { "kind": "SET_STAT_FINAL", "stat": "SHIELD", "value": 0.0 }
    }
  ]
}
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "test(data): add shatter shield event buff fixture"
```

---

## Task 3：新增 failing test（碎盾在 APPLY 前生效）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_shatter_shield_before_apply.gd`

- [ ] **Step 1: 写测试**

```gdscript
extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_shatter_shield_happens_before_shield_absorb() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()

	var attacker = TestBattle.make_entity(7801, ds, enums_rt)
	var defender = TestBattle.make_entity(7802, ds, enums_rt)
	var runtime = TestBattle.make_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var hp_id := ds.stat_id("HP")
	var shield_id := ds.stat_id("SHIELD")

	# baseline：有盾，没碎盾 -> 本次伤害优先被盾吸收，HP 不变
	defender.buffs.apply_buff(defender.stats, "buff_shield_50", 7802)
	var hp0 := float(defender.stats.get_final(hp_id))
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 30.0, replay, 1, tags_mask, runtime)
	assert_true(is_equal_approx(float(defender.stats.get_final(hp_id)), hp0))
	assert_eq(float(defender.stats.get_final(shield_id)), 20.0) # 50-30

	# reset：重新上盾
	defender = TestBattle.make_entity(7803, ds, enums_rt)
	attacker = TestBattle.make_entity(7804, ds, enums_rt)
	runtime = TestBattle.make_runtime([attacker, defender])
	defender.buffs.apply_buff(defender.stats, "buff_shield_50", 7803)

	# 有碎盾 buff：应在 APPLY 阶段把盾置0，本次伤害直接扣HP
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_shatter_shield", 7804)
	hp0 = float(defender.stats.get_final(hp_id))
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 30.0, replay, 2, tags_mask, runtime)
	assert_eq(float(defender.stats.get_final(shield_id)), 0.0)
	assert_true(float(defender.stats.get_final(hp_id)) < hp0)
	assert_eq(float(defender.stats.get_final(hp_id)), hp0 - 30.0)
```

- [ ] **Step 2: 提交 failing test**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_event_shatter_shield_before_apply.gd
git -C godot-buff commit -m "test(d): add shatter shield event test"
```

---

## Task 4：运行时实现 filters/actions（让测试通过）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 扩展 OmniEventIndex.Listener 字段**

在 `event_index.gd` 的 `class Listener` 增加：
```gdscript
var filter_require_hit: bool = false
var filter_stat_scope: String = ""
var filter_stat: String = ""
var filter_stat_op: String = ""
var filter_stat_value: float = 0.0

var action_stat: String = ""
```

- [ ] **Step 2: _register_triggers_for_instance 解析新 filters/action**

在 `buff_core.gd` 的 `_register_triggers_for_instance` 中：
- `l.filter_require_hit = bool(filters.get("require_hit", false))`
- 解析 `filters.stat_threshold`（Dictionary）：
  - `l.filter_stat_scope = String(st.get("scope",""))`
  - `l.filter_stat = String(st.get("stat",""))`
  - `l.filter_stat_op = String(st.get("op",""))`
  - `l.filter_stat_value = float(st.get("value", 0.0))`
- 解析 action：
  - 当 `kind=="SET_STAT_FINAL"`：
    - `l.action_stat = String(action.get("stat",""))`
    - `l.action_value = float(action.get("value", 0.0))`（复用现有字段）

- [ ] **Step 3: emit_event 实现 filters**

在 `emit_event` 的循环里（tag_mask_any 后）增加：
- require_hit：
```gdscript
if l.filter_require_hit and (not bool(ctx.hit)):
    continue
```
- stat_threshold：
  - 从 `ctx.meta.runtime` 取 `stats_by_entity`
  - 用 `_resolve_scope_entity_id(l.filter_stat_scope, ctx)` 得到实体ID
  - 读取 `stat_id = ds.stat_id(l.filter_stat)`，得到 `lhs = stats.get_final(stat_id)`
  - 按 op 比较 `lhs` 与 `l.filter_stat_value`

- [ ] **Step 4: emit_event 实现 action SET_STAT_FINAL**

在 `match l.action_kind` 中增加分支：
```gdscript
"SET_STAT_FINAL":
    _set_stat_final_from_event(l, ctx)
```

并新增函数（参考 _apply_buff_from_event 获取 runtime 的方式）：
```gdscript
func _set_stat_final_from_event(l: OmniEventIndex.Listener, ctx: RefCounted) -> void:
    if l.action_stat == "":
        return
    if not ctx.has_meta("runtime"):
        return
    var runtime: Dictionary = ctx.get_meta("runtime")
    var stats_by_entity: Dictionary = runtime.get("stats_by_entity", {})
    var target_eid := _resolve_scope_entity_id(l.scope, ctx)
    var target_stats: OmniStatsComponent = stats_by_entity.get(target_eid, null)
    if target_stats == null:
        return
    var sid := ds.stat_id(l.action_stat)
    if sid < 0:
        return
    var desired := float(l.action_value)
    var cur := float(target_stats.get_final(sid))
    target_stats.add_base(sid, desired - cur)
```

- [ ] **Step 5: 全量 GUT**

- [ ] **Step 6: 提交实现**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/event_index.gd addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m "feat(d): add require_hit/stat_threshold filters and SET_STAT_FINAL action"
```

