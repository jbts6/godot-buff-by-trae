# act_demo_max_hp_up（MAX_HP +30% / 3回合 / 可刷新）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `rpg_tests` 数据集与 `turn_skill_system` 中新增一个“给自己上 MAX_HP +30%（持续3回合、重复施放刷新）”的主动技能，并在 TurnManager demo 中用该技能替代脚本注入，验证同回合资源同步（保持百分比 + floor）仍正确。

**Architecture:**  
- BUFF 放在 `res://data/rpg_tests/buff_defs.json`，通过 modifier 影响 `MAX_HP` 的 final。  
- 技能放在 `res://addons/turn_skill_system/data/skills/active/`，通过 `apply_buff` effect（scope=caster）调用 OmniBuffAdapter.apply_buff。  
- demo 仅负责施放技能与打印验证；资源同步仍由 TurnManager 的 `sync_resources_keep_ratio(actor)` 在 `ACTION_FINISHED` 后执行。

**Tech Stack:** Godot 4.7, GDScript, OmniBuff, TurnSkillSystem, TurnManager, GUT。

---

## Task 1（RED）: 新增 GUT 冒烟测试（技能能成功 apply_buff）

**Files:**
- Create: `res://addons/turn_skill_system/tests/test_act_demo_max_hp_up_apply_buff_smoke.gd`

- [ ] Step 1: 写测试，目标是“最小闭环”：
  - 加载 rpg_tests dataset（参考你现有 demo 的 manifest 编译方式）
  - 构造一个 unit（entity_id/camp/cell/stats/buffs/is_dead/get_speed 可最小化）
  - 构建 runtime_dict（stats_by_entity/buff_by_entity）
  - 初始化 TurnSkillRuntime：`ensure_ready()`，设置 grid units，调用 `TurnSkillRuntime.omnibuff.setup(ds,enums_rt,runtime_dict)`
  - 调用 `SkillRuntime.cast_to_cell("act_demo_max_hp_up", caster, caster.cell, extra)`（extra 含 dataset/enums_rt/runtime_dict/grid/turn_index）
  - 断言 result.ok == true
  - 断言 `MAX_HP` final 增加（对比 cast 前后的 get_final）
- [ ] Step 2: 运行 GUT 确认 FAIL（此时还没有技能 json / buff_defs 条目）

---

## Task 2（GREEN）: 在 rpg_tests 增加 buff_demo_max_hp_pct_30_3t

**Files:**
- Modify: `res://data/rpg_tests/buff_defs.json`

- [ ] Step 1: 在 `buffs` 数组中新增条目（保持 JSON 风格与缩进一致）：
```json
{
  "id": "buff_demo_max_hp_pct_30_3t",
  "name": "示例：MAX_HP +30%（3回合，可刷新）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "TURNS", "turns": 3, "tick_phase": "TURN_END" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "MAX_HP", "op": "MUL", "phase": "PERCENT", "priority": 110, "value": 0.30 }
  ],
  "triggers": []
}
```
- [ ] Step 2: 重新运行 GUT（仍应 FAIL，因为技能还没加）

---

## Task 3（GREEN）: 新增技能 act_demo_max_hp_up（apply_buff scope=caster）

**Files:**
- Create: `res://addons/turn_skill_system/data/skills/active/act_demo_max_hp_up.json`
- Modify: `res://addons/turn_skill_system/data/skills/index.json`

- [ ] Step 1: 新增技能 JSON：
```json
{
  "version": 1,
  "id": "act_demo_max_hp_up",
  "type": "active",
  "name": "示例：强身（MAX_HP+30%）",
  "desc": "给自己施加 MAX_HP +30%（3回合，可刷新）。",
  "tags": ["BUFF"],
  "targeting": {
    "rule": "single_cell",
    "camp": "ally"
  },
  "on_cast": [
    {
      "kind": "apply_buff",
      "params": { "buff_id": "buff_demo_max_hp_pct_30_3t", "scope": "caster" }
    }
  ],
  "on_hit": []
}
```
- [ ] Step 2: 更新 `index.json` 的 skills 数组，新增条目：
```json
{
  "id": "act_demo_max_hp_up",
  "type": "active",
  "path": "res://addons/turn_skill_system/data/skills/active/act_demo_max_hp_up.json",
  "name": "示例：强身（MAX_HP+30%）",
  "tags": ["BUFF"],
  "mtime_unix": 0
}
```
- [ ] Step 3: 运行 GUT，确认 Task 1 冒烟测试 PASS

---

## Task 4: Demo 改造（用技能驱动 MAX_HP 变化，移除脚本注入）

**Files:**
- Modify: `res://addons/turn_manager/demo/demo_battle.gd`

- [ ] Step 1: 删除/禁用 demo 里 `action_finished` 事件回调中“直接 add_base(MAX_HP,+100)”的代码段
- [ ] Step 2: 在 `action_requested` 回调中加入规则：
  - 若 actor.entity_id == 1 且 turn_index == 1：提交 `act_demo_max_hp_up`，primary_cell 使用 actor.cell
  - 否则继续用 `act_demo_single`
- [ ] Step 3: 保留打印 `HP/MAX_HP` 的日志，用于验证同回合资源同步仍生效（保持百分比 + floor）
- [ ] Step 4: 手动运行 `res://addons/turn_manager/demo/demo_battle.tscn` 验收：
  - 第 1 回合能看到 MAX_HP 提升来自技能/buff
  - TurnManager 在 ACTION_FINISHED 后同步 HP
  - 战斗最终 `battle_ended`

---

## Task 5（可选）: 文档补充

**Files:**
- Modify: `res://addons/turn_skill_system/data/skills/index.json`（如有生成/mtime 策略要求则同步）
- Modify: `res://addons/turn_manager/README.md` 或 `res://addons/turn_skill_system/README.md`

- [ ] Step 1: 记录该 demo skill/buff 的用途：验证 MAX_* 变化 + 资源同步 + 持续时间刷新

---

## Self-Review（计划自检）
- [ ] buff_defs：存在 `buff_demo_max_hp_pct_30_3t` 且 schema 与现有 buff_defs 一致
- [ ] skill：`act_demo_max_hp_up` 能被 index.json 收录并可 cast
- [ ] apply_buff：走 OmniBuffAdapter.apply_buff（不绕开）
- [ ] demo：不再脚本改 MAX_HP，改用技能驱动；资源同步依旧生效

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-19-act-demo-max-hp-up-implementation-plan.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

