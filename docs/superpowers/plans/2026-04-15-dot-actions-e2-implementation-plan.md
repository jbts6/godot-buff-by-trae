# DOT Actions (E2: Stack Manipulation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 E2：通过事件 action 操作目标身上的 DOT 实例（翻倍/加减/设定/清除 stacks），并在操作后刷新 duration（remaining_turns=turns）；支持按 dot_buff_id 与 dot_tags_mask_any 筛选；全程有 GUT 单测覆盖且不破坏驱散相关测试。

**Architecture:** 先更新数据协议治理（enums.action_kind + validators.allowed_action），再加 rpg_tests fixtures（4 个触发 buff + 复用现有 DOT buff），写 failing tests（验证 stacks 变化、duration 刷新、筛选生效、不会影响 FIRE/POISON 分段聚合），最后在 `BuffCore.emit_event` 增加 4 个 action 分支，内部通过 `ctx.meta.runtime` 取得 `buff_by_entity`，只遍历目标的 `dots_by_target[target]` 并就地修改 DotInstance。最后全量回归。

**Tech Stack:** Godot 4.7 + GDScript + GUT + rpg_tests。

---

## 0) 文件清单

**数据：**
- Modify: `godot-buff/data/base_demo/enums.json`
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

**编译校验：**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dot_actions_mul_add_set_clear.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dot_actions_filter_by_tags.gd`

---

## Task 1：更新 enums + validators（协议治理）

**Files:**
- Modify: `godot-buff/data/base_demo/enums.json`
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

- [ ] **Step 1: enums.action_kind 增加 4 个动作**

在 `enums.action_kind` 末尾追加：
```json
"DOT_MUL_STACKS",
"DOT_ADD_STACKS",
"DOT_SET_STACKS",
"DOT_CLEAR"
```

- [ ] **Step 2: validators 允许 action 新字段**

在 `validators.gd` 的 `allowed_action` 扩展为：
```gdscript
var allowed_action := {
  "kind": true,
  "value": true,
  "buff_id": true,
  "apply_buff_id": true,
  "chance": true,
  "dot_buff_id": true,
  "dot_tags_mask_any": true
}
```

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add data/base_demo/enums.json addons/omnibuff/config/compiler/validators.gd
git -C godot-buff commit -m "feat(e2): add dot action kinds and schema fields"
```

---

## Task 2：补齐 rpg_tests fixtures（4 个触发 buff）

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 新增 4 个触发 buff（挂在攻击者身上）**

说明：都用 `event_type=DAMAGE`、`event_phase=AFTER_DEAL`、`scope=TARGET`，并保留 `tag_mask_any=["BUFF"]` 作为监听子集过滤。

1) 翻倍（MUL*2），按 buff_id 精确筛选：
```json
{
  "id": "buff_on_hit_dot_mul2",
  "name": "E2测试：命中后DOT翻倍",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [],
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "AFTER_DEAL",
      "scope": "TARGET",
      "filters": { "tag_mask_any": ["BUFF"], "require_hit": true },
      "action": { "kind": "DOT_MUL_STACKS", "dot_buff_id": "buff_dot_fire_stack_3t", "value": 2 }
    }
  ]
}
```

2) 加减层（delta=-1），按 buff_id：
```json
{
  "id": "buff_on_hit_dot_add_minus1",
  "name": "E2测试：命中后DOT减1层",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [],
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "AFTER_DEAL",
      "scope": "TARGET",
      "filters": { "tag_mask_any": ["BUFF"], "require_hit": true },
      "action": { "kind": "DOT_ADD_STACKS", "dot_buff_id": "buff_dot_fire_stack_3t", "value": -1 }
    }
  ]
}
```

3) 设定层（SET=3），按 buff_id：
```json
{
  "id": "buff_on_hit_dot_set3",
  "name": "E2测试：命中后DOT设为3层",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [],
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "AFTER_DEAL",
      "scope": "TARGET",
      "filters": { "tag_mask_any": ["BUFF"], "require_hit": true },
      "action": { "kind": "DOT_SET_STACKS", "dot_buff_id": "buff_dot_fire_stack_3t", "value": 3 }
    }
  ]
}
```

4) 清除（CLEAR），按 tags_mask_any（例如只清 POISON）：
```json
{
  "id": "buff_on_hit_dot_clear_poison",
  "name": "E2测试：命中后清除POISON DOT",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [],
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "AFTER_DEAL",
      "scope": "TARGET",
      "filters": { "tag_mask_any": ["BUFF"], "require_hit": true },
      "action": { "kind": "DOT_CLEAR", "dot_tags_mask_any": ["POISON"] }
    }
  ]
}
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "test(data): add E2 dot action trigger fixtures"
```

---

## Task 3：新增 failing tests（MUL/ADD/SET/CLEAR + duration 刷新）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dot_actions_mul_add_set_clear.gd`

- [ ] **Step 1: 写测试**

测试思路（不依赖内部私有字段，尽量用行为断言）：
- 给 defender 先挂 `buff_dot_fire_stack_3t`（stacks=1）
- attacker 挂对应触发 buff
- attacker 对 defender 打一段伤害，触发 AFTER_DEAL -> DOT action
- 然后推进到下一回合 TurnStart tick
- 用 `DotTrace.base_damage/final_damage` 或 defender HP 变化推导 stacks 是否变化
- duration 刷新：通过 “先让 DOT tick 2 次（剩 1 turn），再触发 action，应能再 tick 3 次” 的方式验证

最小骨架：
```gdscript
extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_dot_mul_add_set_clear_and_refresh_turns() -> void:
	# 逐子场景：MUL / ADD(-1) / SET / CLEAR
	pass
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_dot_actions_mul_add_set_clear.gd
git -C godot-buff commit -m "test(e2): add dot action mul/add/set/clear tests"
```

---

## Task 4：新增 failing test（按 tags_mask_any 筛选）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dot_actions_filter_by_tags.gd`

- [ ] **Step 1: 写测试**

- defender 同时有 FIRE 与 POISON DOT（各自两来源）
- attacker 挂 `buff_on_hit_dot_clear_poison`
- 攻击触发后：
  - POISON DotInstance 应被清除（后续 tick 只剩 FIRE）
  - FIRE 不受影响

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_dot_actions_filter_by_tags.gd
git -C godot-buff commit -m "test(e2): add dot action tag-filter tests"
```

---

## Task 5：运行时实现（Listener 承载字段 + emit_event 执行动作）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: Listener 增加 dot action 字段**

在 `event_index.gd`：
```gdscript
var action_dot_buff_id: String = ""
var action_dot_tag_mask_any: int = 0
```

- [ ] **Step 2: 注册时解析 action.dot_buff_id / action.dot_tags_mask_any**

在 `_register_triggers_for_instance`：
```gdscript
if action.has("dot_buff_id"):
    l.action_dot_buff_id = String(action.get("dot_buff_id",""))
if action.has("dot_tags_mask_any"):
    var arr: Array = action.get("dot_tags_mask_any", [])
    l.action_dot_tag_mask_any = int(enums_rt.tag_mask(arr))
```

- [ ] **Step 3: emit_event 增加 4 个 action 分支**

在 `match l.action_kind` 增加：
- `DOT_MUL_STACKS`
- `DOT_ADD_STACKS`
- `DOT_SET_STACKS`
- `DOT_CLEAR`

统一调用 helper：
```gdscript
_apply_dot_action_from_event(l, ctx)
```

- [ ] **Step 4: 实现 _apply_dot_action_from_event**

要点：
- 从 `ctx.meta.runtime` 取 `buff_by_entity`
- 解析 action 目标实体 `eid := _resolve_scope_entity_id(l.scope, ctx)`
- 取 `target_buff: OmniBuffCore = buff_by_entity.get(eid, null)`
- 从 `target_buff.dots_by_target[eid]` 取 dots 数组
- 按 `action_dot_buff_id` 与 `action_dot_tag_mask_any` 过滤
- 对匹配 DotInstance：
  - stacks 运算
  - clamp 到 max_stack（若存在）
  - 若 stacks<=0 删实例
  - 否则 remaining_turns 重置为 duration.turns
- 回写 dots 数组

- [ ] **Step 5: 全量 GUT**

- [ ] **Step 6: 提交运行时实现**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/event_index.gd addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m "feat(e2): add dot stack manipulation actions"
```

