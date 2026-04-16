# OmniBuff Phase 1 Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 扩展 EventIndex 的 action.kind 白名单，落地 ADD_SHIELD/HEAL/DISPEL/LIFESTEAL/REFLECT_DAMAGE，并配套 validators + tests + demo scenarios + HUD 输出，形成可回归的 MOBA 高频动作集合。

**Architecture:** 在现有 `OmniEventIndex.Listener` 增加少量 payload 字段；`BuffCore` 注册时解析；`emit_event` 中执行动作（通过 ctx.meta.runtime 访问 stats/buffs）。反伤用“直接扣 HP”避免递归伤害链；吸血在 AFTER_DEAL 基于 ctx.final_damage 计算治疗。

**Tech Stack:** Godot 4.7 + GDScript + OmniBuffCore + OmniEventIndex + OmniDamagePipeline + GUT。

---

## 0) 文件清单

- Modify: `godot-buff/data/base_demo/enums.json`
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_actions_phase1.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_actions_phase1.gd.uid`
- Modify (data): `godot-buff/data/rpg_tests/buff_defs.json`（测试/场景用 buff）

---

## Task 1：写 failing tests（RED）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_actions_phase1.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_actions_phase1.gd.uid`

- [ ] **Step 1: 创建测试文件骨架**

```gdscript
extends GutTest

const ReplayScript := preload(\"res://addons/omnibuff/runtime/core/replay.gd\")
const TestDataset := preload(\"res://addons/omnibuff/tests/helpers/test_dataset.gd\")
const TestBattle := preload(\"res://addons/omnibuff/tests/helpers/test_battle.gd\")

func test_heal_action_increases_hp() -> void:
    pass
```

- [ ] **Step 2: 增加 5 个用例（初始应失败）**

1) HEAL：AFTER_TAKE 给 SELF 加 HP
2) ADD_SHIELD：BEFORE_TAKE 给 SELF 加盾，下一次伤害 absorbed_shield>0 且 final_damage 下降
3) DISPEL：AFTER_TAKE 驱散 DEBUFF，DOT 实例也被清理
4) LIFESTEAL：AFTER_DEAL heal=ctx.final_damage*ratio
5) REFLECT_DAMAGE：AFTER_TAKE attacker HP -= ctx.final_damage*ratio（不走 pipeline）

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_event_actions_phase1.gd addons/omnibuff/tests/rpg/test_event_actions_phase1.gd.uid
git -C godot-buff commit -m \"test(actions): add failing coverage for phase1 actions\"
```

---

## Task 2：更新 enums.action_kind 白名单

**Files:**
- Modify: `godot-buff/data/base_demo/enums.json`

- [ ] **Step 1: action_kind 追加**
追加：
- `ADD_SHIELD`
- `HEAL`
- `DISPEL`
- `LIFESTEAL`
- `REFLECT_DAMAGE`

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add data/base_demo/enums.json
git -C godot-buff commit -m \"feat(enums): add phase1 action kinds\"
```

---

## Task 3：扩展 Listener payload（event_index.gd）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`

- [ ] **Step 1: Listener 增加字段（默认值）**

```gdscript
var action_ratio: float = 0.0
var action_dispel_mode: String = \"\"
var action_dispel_tag: String = \"\"
var action_dispel_buff_type: String = \"\"
var action_dispel_source_scope: String = \"\"
var action_include_implicit: bool = false
```

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/event_index.gd
git -C godot-buff commit -m \"feat(actions): extend listener payload fields\"
```

---

## Task 4：解析 action payload（BuffCore 注册）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 在 _register_triggers_for_instance() 解析**

规则：
- HEAL/ADD_SHIELD：使用 `value`
- LIFESTEAL/REFLECT_DAMAGE：使用 `ratio`
- DISPEL：`mode/tag/source/buff_type/include_implicit`

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m \"feat(actions): parse phase1 action payloads\"
```

---

## Task 5：实现动作执行（BuffCore.emit_event）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 实现 helper（最小）**

1) `_heal_from_event`：HP += value（target scope）
2) `_add_shield_from_event`：SHIELD += value
3) `_dispel_from_event`：调用 `dispel_by_tag/source/type`
4) `_lifesteal_from_event`：heal = ctx.final_damage*ratio，对 SOURCE 生效（建议 scope 强制 SOURCE）
5) `_reflect_from_event`：attacker HP -= ctx.final_damage*ratio（scope=SOURCE）

- [ ] **Step 2: 接入 match 分支**

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m \"feat(actions): implement phase1 actions\"
```

---

## Task 6：validators 扩展（schema 治理）

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

- [ ] **Step 1: action 字段白名单允许 ratio/mode/tag/source/buff_type/include_implicit**

- [ ] **Step 2: action.kind 字段要求矩阵**

- HEAL/ADD_SHIELD：必须 `value>0`
- LIFESTEAL/REFLECT_DAMAGE：必须 `ratio` 且 0..1
- DISPEL：按 mode 要求 tag/source/buff_type

并给出 JSON hint。

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/config/compiler/validators.gd
git -C godot-buff commit -m \"feat(validate): support phase1 actions\"
```

---

## Task 7：HUD 输出增强（Listeners action 摘要）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

- [ ] **Step 1: 输出 HEAL/ADD_SHIELD/LIFESTEAL/REFLECT/DISPEL 的摘要**

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/debug_hud.gd
git -C godot-buff commit -m \"feat(debug): show phase1 actions in listeners tab\"
```

---

## Task 8：tests/demo 数据与场景

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: 添加测试用 buff_defs（每个 action 1 个）**
- `buff_action_heal_30`
- `buff_action_add_shield_50`
- `buff_action_dispel_debuff`
- `buff_action_lifesteal_20p`
- `buff_action_reflect_30p`

- [ ] **Step 2: 增加 demo scenarios（对应 5 个 action）**

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add data/rpg_tests/buff_defs.json addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m \"feat(demo): add scenarios for phase1 actions\"
```

---

## 最终验证

- [ ] 跑 `test_event_actions_phase1.gd` 全绿
- [ ] 抽样跑 2 个旧 rpg_tests 用例仍绿
- [ ] Demo 中 5 个 action scenario 可复现，并能在 HUD 中解释触发链

