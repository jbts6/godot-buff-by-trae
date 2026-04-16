# Set Bonus Manager Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `addons/` 下新增一个独立插件 `omni_set_bonuses`，用于根据装备列表判定套装生效，并通过 `apply_buff/remove_by_buff_id` 下发/撤销套装 buff（完全不侵入 OmniBuff 内部）。

**Architecture:** 先写 failing tests（用 FakeBuffCore 记录 apply/remove 调用与幂等），再实现 `SetBonusManager` 核心逻辑与最小文档；最后加一个与 OmniBuff 的集成测试（使用真实 BuffCore + 测试数据 set buffs）。

**Tech Stack:** Godot 4.7 + GDScript + GUT + OmniBuff（作为依赖）。

---

## 0) 文件清单

**插件文件：**
- Create: `godot-buff/addons/omni_set_bonuses/plugin.cfg`
- Create: `godot-buff/addons/omni_set_bonuses/plugin.gd`（可选：空 EditorPlugin）

**运行时代码：**
- Create: `godot-buff/addons/omni_set_bonuses/runtime/set_bonus_manager.gd`
- Create: `godot-buff/addons/omni_set_bonuses/runtime/set_defs.gd`（可选：类型/工具）

**文档：**
- Create: `godot-buff/addons/omni_set_bonuses/docs/README.md`

**测试：**
- Create: `godot-buff/addons/omni_set_bonuses/tests/test_set_bonus_manager_unit.gd`
- Create: `godot-buff/addons/omni_set_bonuses/tests/test_set_bonus_manager_integration_with_omnibuff.gd`

**测试数据：**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`（新增 set_*_2pc/4pc 示例）

---

## Task 1：单元测试（FakeBuffCore，锁定幂等与 diff）

**Files:**
- Create: `godot-buff/addons/omni_set_bonuses/tests/test_set_bonus_manager_unit.gd`

- [ ] **Step 1: 写 failing test + FakeBuffCore**

```gdscript
extends GutTest

const SBM = preload("res://addons/omni_set_bonuses/runtime/set_bonus_manager.gd")

class FakeBuffCore:
	var applied: Array[String] = []
	var removed: Array[String] = []
	var active: Dictionary = {} # buff_id -> true

	func apply_buff(_stats, buff_id: String, _source_id: int) -> int:
		if not active.has(buff_id):
			applied.append(buff_id)
		active[buff_id] = true
		return 1

	func remove_by_buff_id(_stats, buff_id: String, _scope: String = "ALL", _source_id: int = -1, _include_implicit: bool = false, _force: bool = false) -> int:
		if active.has(buff_id):
			active.erase(buff_id)
			removed.append(buff_id)
			return 1
		return 0

func test_compute_active_buffs() -> void:
	var items: Array = [
		{"item_id":"a", "set_id":"dragon"},
		{"item_id":"b", "set_id":"dragon"},
		{"item_id":"c", "set_id":"dragon"},
		{"item_id":"d", "set_id":"dragon"},
	]
	var defs: Dictionary = {"dragon": {2: "set_dragon_2pc", 4: "set_dragon_4pc"}}
	var out: PackedStringArray = SBM.compute_active_set_buffs(items, defs)
	assert_true(out.has("set_dragon_2pc"))
	assert_true(out.has("set_dragon_4pc"))

func test_refresh_is_idempotent_and_diffs() -> void:
	var items4: Array = [
		{"item_id":"a", "set_id":"dragon"},
		{"item_id":"b", "set_id":"dragon"},
		{"item_id":"c", "set_id":"dragon"},
		{"item_id":"d", "set_id":"dragon"},
	]
	var items2: Array = [
		{"item_id":"a", "set_id":"dragon"},
		{"item_id":"b", "set_id":"dragon"},
	]
	var defs: Dictionary = {"dragon": {2: "set_dragon_2pc", 4: "set_dragon_4pc"}}
	var buffs := FakeBuffCore.new()

	SBM.refresh_entity(null, buffs, items4, defs, 1001)
	assert_eq(buffs.applied.size(), 2)

	# second call: idempotent (no new applies)
	SBM.refresh_entity(null, buffs, items4, defs, 1001)
	assert_eq(buffs.applied.size(), 2)

	# downgrade to 2pc: remove 4pc only
	SBM.refresh_entity(null, buffs, items2, defs, 1001)
	assert_true(buffs.removed.has("set_dragon_4pc"))
	assert_false(buffs.removed.has("set_dragon_2pc"))
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omni_set_bonuses/tests/test_set_bonus_manager_unit.gd
git -C godot-buff commit -m "test(set): add unit coverage for set bonus manager"
```

---

## Task 2：实现 SetBonusManager（核心逻辑）

**Files:**
- Create: `godot-buff/addons/omni_set_bonuses/runtime/set_bonus_manager.gd`

- [ ] **Step 1: 实现 compute_active_set_buffs**

```gdscript
static func compute_active_set_buffs(equipped_items: Array, set_defs: Dictionary) -> PackedStringArray:
	# 1) count set_id
	# 2) thresholds satisfied => collect buff_ids
	# 3) return stable order (sort)
```

- [ ] **Step 2: 实现 refresh_entity（diff apply/remove）**

要求：
- desired_buffs：按 compute 结果
- existing_buffs：由插件内部缓存（最小方案）或从 buffs.active/inst_ids 推导（不推荐侵入）
- 最小方案：插件维护 `meta`：`stats.set_meta("set_bonus_active", PackedStringArray)` 作为当前状态

示例：
```gdscript
var prev: PackedStringArray = PackedStringArray(stats.get_meta("set_bonus_active", PackedStringArray()))
```

然后 diff：
- add = desired - prev
- remove = prev - desired

对 remove：`buffs.remove_by_buff_id(stats, buff_id, "ALL", source_entity_id, false, true)`

最后写回 meta：
`stats.set_meta("set_bonus_active", desired)`

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add addons/omni_set_bonuses/runtime/set_bonus_manager.gd
git -C godot-buff commit -m "feat(set): add set bonus manager (apply/remove only)"
```

---

## Task 3：插件骨架 + 文档

**Files:**
- Create: `godot-buff/addons/omni_set_bonuses/plugin.cfg`
- Create: `godot-buff/addons/omni_set_bonuses/plugin.gd`
- Create: `godot-buff/addons/omni_set_bonuses/docs/README.md`

- [ ] **Step 1: plugin.cfg**

```ini
[plugin]
name="Omni Set Bonuses"
description="Set bonus manager (apply/remove buffs based on equipped items)"
author="jbts6"
version="0.1.0"
script="plugin.gd"
```

- [ ] **Step 2: plugin.gd（最小空实现）**

```gdscript
@tool
extends EditorPlugin
```

- [ ] **Step 3: README.md**
包含：数据结构、典型用法、推荐 tag（SET_BONUS）、幂等刷新范式。

- [ ] **Step 4: 提交**

```bash
git -C godot-buff add addons/omni_set_bonuses/plugin.cfg addons/omni_set_bonuses/plugin.gd addons/omni_set_bonuses/docs/README.md
git -C godot-buff commit -m "docs(set): add plugin scaffold and usage"
```

---

## Task 4：与 OmniBuff 集成测试（真实 apply/remove 生效）

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`
- Create: `godot-buff/addons/omni_set_bonuses/tests/test_set_bonus_manager_integration_with_omnibuff.gd`

- [ ] **Step 1: 在 rpg_tests 增加两个 set buff**
例如：
- `set_dragon_2pc`：`ATK + 0.10 (MUL/PERCENT layer=0)`
- `set_dragon_4pc`：`ATK + 0.20 (MUL/PERCENT layer=1)`（用于验证 percent layers）

- [ ] **Step 2: 集成测试**
流程：
1) load_rpg_tests(true) + make_entity
2) refresh_entity(items2) => ATK 变化到 `base*(1+0.1)`
3) refresh_entity(items4) => ATK 变化到 `base*(1+0.1)*(1+0.2)`
4) refresh_entity(items0) => ATK 回到 base

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add data/rpg_tests/buff_defs.json addons/omni_set_bonuses/tests/test_set_bonus_manager_integration_with_omnibuff.gd
git -C godot-buff commit -m "test(set): integration coverage with omnibuff"
```

