# 资源型属性（当前/最大）同步（HP/MP/RAGE）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 omnibuff + turn_skill_system + turn_manager 基础上，支持 HP/MP/RAGE 的“当前/最大”资源对，并实现“MAX 变化时保持百分比（floor）”的同步机制；同步范围仅当前行动者，但能覆盖“本回合内提升 MAX_*”的情况。

**Architecture:** 通过 TurnManager 内的快照字典 `resource_snapshot_by_entity` + 一个资源同步函数 `sync_resources_keep_ratio(actor)` 实现。同步时机固定两处：TurnStart tick 后、ActionFinished 后。数据集层新增 MAX_* 与 MP/RAGE，并将 HP 的 derived 迁移到 MAX_HP。用 GUT 测试锁定公式与回合内 MAX 变化行为。

**Tech Stack:** Godot 4.7, GDScript, OmniBuff, TurnSkillSystem, TurnManager, GUT。

---

## 0) File structure（本计划将创建/修改的文件）

### Modify（数据集）
- [ ] `res://data/rpg_tests/stat_defs.json`
- [ ] `res://data/base_demo/enums.json`（仅当需要在 enums 里显式声明资源 stat id；取决于你的 schema 策略）

### Modify（TurnManager）
- [ ] `res://addons/turn_manager/runtime/turn_manager.gd`
- [ ] `res://addons/turn_manager/demo/demo_battle.gd`（增加一个“回合内 MAX 变化”的演示步骤）

### Create（TurnManager 测试）
- [ ] `res://addons/turn_manager/tests/test_resource_sync_keep_ratio.gd`

### Modify（文档，可选）
- [ ] `res://addons/turn_manager/README.md`

---

## Task 1（RED）: 新增 GUT 测试：同步公式（floor + 百分比）

**Files:**
- Create: `res://addons/turn_manager/tests/test_resource_sync_keep_ratio.gd`

- [ ] Step 1: 写一个纯逻辑测试，不依赖真实数据集：
  - 构造 FakeStats（支持 get_final + add_base）
  - 构造 FakeDataset（支持 stat_id：HP/MAX_HP/MP/MAX_MP/RAGE/MAX_RAGE）
  - 构造最小 TurnManager（或直接调用你将实现的同步函数）
- [ ] Step 2: 用例 1：
  - old_max=100 old_cur=50（ratio=0.5）
  - new_max=121
  - 期望 new_cur=floor(0.5*121)=60
- [ ] Step 3: 用例 2（clamp）：
  - old_cur > old_max 时 ratio 视为 1
  - new_cur = new_max
- [ ] Step 4: 运行 GUT 确认 FAIL（因为同步函数与快照机制尚不存在）

---

## Task 2（GREEN）: TurnManager 增加资源快照与同步函数（仅 actor）

**Files:**
- Modify: `res://addons/turn_manager/runtime/turn_manager.gd`

- [ ] Step 1: 增加字段：
  - `var resource_snapshot_by_entity: Dictionary = {}`
- [ ] Step 2: 增加资源对配置（字符串对）：
  - (HP, MAX_HP)、(MP, MAX_MP)、(RAGE, MAX_RAGE)
- [ ] Step 3: 实现 `sync_resources_keep_ratio(actor)`：
  - 获取 entity_id
  - 为 actor 初始化 snapshot（首次调用时 snapshot=max）
  - 对每个资源对：
    - cur_id = ds.stat_id(CUR)
    - max_id = ds.stat_id(MAX)
    - old_max = snapshot[max_id]（无则取当前 max 初始化）
    - old_cur = stats.get_final(cur_id)
    - new_max = stats.get_final(max_id)
    - ratio + floor + clamp
    - 用 delta 方式写回 CUR：`stats.add_base(cur_id, new_cur - old_cur)`
    - 更新 snapshot[max_id]=new_max
- [ ] Step 4: 运行 GUT，确认 Task 1 通过

---

## Task 3（RED）: 新增测试：回合内 MAX 变化也能保持比例

**Files:**
- Modify: `res://addons/turn_manager/tests/test_resource_sync_keep_ratio.gd`

- [ ] Step 1: 在测试中模拟：
  - 初始：HP=50, MAX_HP=100（ratio=0.5），并调用一次 sync（建立 snapshot=100）
  - 模拟“行动中提高 MAX_HP”：把 MAX_HP 增加到 200
  - 再调用一次 sync
  - 期望：HP=100（floor(0.5*200)）
- [ ] Step 2: 运行 GUT 确认 FAIL（因为同步时机还没接到 TurnManager 流程里；或你的实现尚未处理 snapshot）

---

## Task 4（GREEN）: 将同步接入 TurnManager 两个时机（TurnStart + ActionFinished）

**Files:**
- Modify: `res://addons/turn_manager/runtime/turn_manager.gd`

- [ ] Step 1: 在 `TURN_START` 阶段（`on_turn_start` tick + aura refresh 后，进入 REQUEST_ACTION 前）调用：
  - `sync_resources_keep_ratio(_current_actor)`
- [ ] Step 2: 在 `RESOLVE_ACTION` 阶段（`ACTION_FINISHED` emit 后，进入 TURN_END 前）调用：
  - `sync_resources_keep_ratio(_current_actor)`
- [ ] Step 3: 运行 GUT，确认 Task 3 通过

---

## Task 5（数据集变更）: 新增 MAX_* 与 MP/RAGE，并迁移 derived

**Files:**
- Modify: `res://data/rpg_tests/stat_defs.json`

- [ ] Step 1: 新增 stat：
  - MAX_HP（clamp=true, min=0）
  - MP / MAX_MP（clamp=true, min=0）
  - RAGE / MAX_RAGE（clamp=true, min=0）
- [ ] Step 2: 将当前 HP 的 derived（from STR）迁移到 MAX_HP
- [ ] Step 3: 调整 HP：
  - 保持 clamp=true，但不再 derived
- [ ] Step 4: 运行项目 demo（人工）验证：
  - 初始化能拿到 stat_id("MAX_HP") 等
  - 同步机制不报 missing stat

---

## Task 6（demo 验收）: 在 demo 中加入“回合内 MAX 变化”的可见演示

**Files:**
- Modify: `res://addons/turn_manager/demo/demo_battle.gd`

- [ ] Step 1: 在某个固定 turn（例如 turn 1 的 actor）行动结算后，模拟一个 MAX_HP 提升（例如 add_base(MAX_HP, +100)）
- [ ] Step 2: 打印同步前后 HP/MAX_HP（至少一次），验证：
  - 同步后 HP 按比例变为 floor(old_ratio * new_max)
- [ ] Step 3: 人工运行 demo，确认战斗仍能结束（battle_ended）

---

## Task 7（可选）: 文档更新

**Files:**
- Modify: `res://addons/turn_manager/README.md`

- [ ] Step 1: 增加“资源型属性规则”章节：
  - 资源对列表
  - 保持百分比 + floor 的规则
  - 同步时机（TurnStart + ActionFinished，仅 actor）

---

## Self-Review（计划自检）

- [ ] 覆盖 Spec：资源对（HP/MP/RAGE）齐全
- [ ] 同步规则：保持百分比 + floor + clamp
- [ ] 快照：保证回合内 MAX 变化同步正确
- [ ] 同步范围：仅当前行动者
- [ ] 测试：公式与回合内 MAX 变化都有回归

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-19-resource-sync-current-max-implementation-plan.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

