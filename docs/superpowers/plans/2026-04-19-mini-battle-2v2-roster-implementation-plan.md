# 2v2 小型战斗 Demo（主角/队友 vs Boss/随从）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 基于现有 omnibuff + turn_skill_system + turn_manager，落地一个可跑的 2v2 demo：主角（2 主动含 AOE + 开战加速被动）、队友（治疗主动 + 减伤光环）、Boss（2 主动含 AOE）、随从（单体）。满足“Boss 基础速度最高，但开战后主角靠被动先手”“AOE 至少 2 回合冷却”的约束，并能作为稳定 demo 测试。

**Architecture:**  
- 属性：使用 omnibuff 的 `StatsComponent`，新增 `SPEED` stat，unit.get_speed() 从 stats.get_final(SPEED) 读取。  
- 被动/光环：走 turn_skill_system 的 `PassiveManager/AuraManager`，触发点统一用 `BattleEventBus`。  
- 冷却：在 TurnManager（或 demo AI）维护 per-unit per-skill cooldown map；AOE 技能 cooldown_turns>=2。  
- 先手：新增 `battle_started` 事件，TurnManager 在首轮排队前 emit；主角被动监听并 apply SPEED buff。
 - 额外规则（已更新）：Boss 的所有主动技能均有冷却；当角色所有技能在冷却时改为普攻（普攻不进入冷却）。

**Tech Stack:** Godot 4.7, GDScript, OmniBuff, TurnSkillSystem, TurnManager, GUT。

---

## 0) File structure（将创建/修改的文件）

### Modify（omnibuff 数据集）
- [ ] `res://data/rpg_tests/stat_defs.json`（新增 SPEED）
- [ ] `res://data/rpg_tests/buff_defs.json`（新增主角 SPEED buff；复用/必要时新增减伤 buff）

### Create/Modify（turn_skill_system skills）
- [ ] Create: `res://addons/turn_skill_system/data/skills/active/act_hero_strike.json`
- [ ] Create: `res://addons/turn_skill_system/data/skills/active/act_hero_whirlwind.json`
- [ ] Create: `res://addons/turn_skill_system/data/skills/passive/pas_hero_battle_haste.json`
- [ ] Create: `res://addons/turn_skill_system/data/skills/active/act_ally_heal.json`
- [ ] Create: `res://addons/turn_skill_system/data/skills/aura/aur_ally_guard.json`
- [ ] Create: `res://addons/turn_skill_system/data/skills/active/act_ally_basic.json`
- [ ] Create: `res://addons/turn_skill_system/data/skills/active/act_boss_crush.json`
- [ ] Create: `res://addons/turn_skill_system/data/skills/active/act_boss_quake.json`
- [ ] Create: `res://addons/turn_skill_system/data/skills/active/act_boss_basic.json`
- [ ] Create: `res://addons/turn_skill_system/data/skills/active/act_minion_stab.json`
- [ ] Modify: `res://addons/turn_skill_system/data/skills/index.json`

### Modify（turn_skill_system runtime）
- [ ] `res://addons/turn_skill_system/runtime/event_names.gd`（新增 BATTLE_STARTED）
- [ ] `res://addons/turn_skill_system/runtime/aura_manager.gd`（新增 range.rule: ally_all，作用于同阵营全体）

### Modify（TurnManager + demo）
- [ ] `res://addons/turn_manager/runtime/turn_manager.gd`（emit BATTLE_STARTED；冷却 map 与递减；为 cast 填充 a_stats/t_stats）
- [ ] `res://addons/turn_manager/demo/demo_battle.gd`（使用新 roster；注册被动/光环；AI 选择技能与冷却）

### Create（测试）
- [ ] `res://addons/turn_manager/tests/test_battle_started_passive_haste.gd`
- [ ] `res://addons/turn_manager/tests/test_cooldown_enforced_for_aoe.gd`

---

## Task 1（RED）: 新增测试——battle_started 事件能触发主角被动并提升 SPEED

**Files:**
- Create: `res://addons/turn_manager/tests/test_battle_started_passive_haste.gd`

- [ ] Step 1: 写 GUT 测试（不改实现）：
  - 构造最小 battle_context（ds/enums/runtime_dict/grid/event_bus + TurnSkillRuntime）
  - 构造 HERO/BOSS 两个 unit（基础 SPEED：Boss > Hero）
  - 注册 HERO 的被动 `pas_hero_battle_haste`
  - 由 TurnManager.start_battle() 触发 battle_started
  - 断言：事件之后 `hero_speed > boss_speed`
- [ ] Step 2: 跑 GUT，确认 FAIL（因为还没有 battle_started 事件与被动/BUFF）
- [ ] Step 3: Commit（仅测试）：
  - `git add ... && git commit -m "test(turn_manager): add battle_started haste test"`

---

## Task 2（GREEN）: 落地 battle_started 事件（EventNames + TurnManager emit）

**Files:**
- Modify: `res://addons/turn_skill_system/runtime/event_names.gd`
- Modify: `res://addons/turn_manager/runtime/turn_manager.gd`

- [ ] Step 1: 在 EventNames 增加 `BATTLE_STARTED = "battle_started"`
- [ ] Step 2: 在 TurnManager.start_battle() 进入首轮排队前 emit：
  - `event_bus.emit_event(EventNames.BATTLE_STARTED, {turn_index, round_index,...})`
- [ ] Step 3: 跑 GUT，确认 Task 1 仍 FAIL（此时还缺 buff_defs + passive skill）
- [ ] Step 4: Commit：
  - `git add ... && git commit -m "feat: emit battle_started event"`

---

## Task 3（GREEN）: 数据集新增 SPEED stat + 主角加速 buff

**Files:**
- Modify: `res://data/rpg_tests/stat_defs.json`
- Modify: `res://data/rpg_tests/buff_defs.json`

- [ ] Step 1: 在 stat_defs.json 新增 `SPEED`（clamp=true, min=0, max=999）
- [ ] Step 2: 在 buff_defs.json 新增 `buff_hero_speed_flat_5_3t`：
  - duration：TURNS=3, tick_phase=TURN_END
  - stack：REPLACE + RESET_TO_MAX
  - effect：SPEED ADD FLAT +5
- [ ] Step 3: 跑 GUT，确认仍 FAIL（被动 skill 尚未加入）
- [ ] Step 4: Commit：
  - `git add ... && git commit -m "feat(rpg_tests): add SPEED stat and hero haste buff"`

---

## Task 4（GREEN）: 新增主角被动 pas_hero_battle_haste（监听 battle_started）

**Files:**
- Create: `res://addons/turn_skill_system/data/skills/passive/pas_hero_battle_haste.json`
- Modify: `res://addons/turn_skill_system/data/skills/index.json`

- [ ] Step 1: 新增被动 JSON（triggers.event = battle_started，apply_buff scope=caster）
- [ ] Step 2: 更新 skills/index.json 注册该 passive
- [ ] Step 3: 跑 GUT，确认 Task 1 PASS
- [ ] Step 4: Commit：
  - `git add ... && git commit -m "feat(turn_skill_system): add hero battle haste passive"`

---

## Task 5（RED）: 新增测试——AOE 技能冷却至少 2 回合且被执行层约束

**Files:**
- Create: `res://addons/turn_manager/tests/test_cooldown_enforced_for_aoe.gd`

- [ ] Step 1: 写测试：
  - 定义一个 AOE skill（cooldown_turns=2）
  - 模拟同一单位连续两回合尝试施放
  - 期望：第二回合被拒绝或 AI 不会选择（根据实现口径二选一并在测试中固定）
- [ ] Step 2: 跑 GUT，确认 FAIL（当前没有冷却系统）
- [ ] Step 3: Commit（仅测试）：
  - `git add ... && git commit -m "test(turn_manager): add cooldown enforcement test"`

---

## Task 6（GREEN）: TurnManager 增加冷却 map 与递减，并用于选择/校验

**Files:**
- Modify: `res://addons/turn_manager/runtime/turn_manager.gd`

- [ ] Step 1: 新增 per-entity cooldown map：
  - `cooldown_by_entity: {eid: {skill_id: turns_remaining}}`
- [ ] Step 2: 在 TurnStart（actor）阶段递减其所有 cooldown（到 0 删 key）
- [ ] Step 3: 在提交命令/执行前校验：
  - 若 skill.cooldown_turns>0 且 cooldown_remaining>0：拒绝（ok=false, errors 包含 cooldown_not_ready）
  - 若允许施放：施放成功后写入 cooldown_remaining=cooldown_turns
  - **普攻例外**：约定 cooldown_turns==0 的技能不进入冷却；当“所有技能都在冷却”时，AI 会退化为普攻
- [ ] Step 4: 跑 GUT，确认 Task 5 PASS
- [ ] Step 5: Commit：
  - `git add ... && git commit -m "feat(turn_manager): enforce per-skill cooldowns"`

---

## Task 7（GREEN）: 新增 8 个技能（主角/队友/Boss/随从）

**Files:**
- Create: `res://addons/turn_skill_system/data/skills/active/act_hero_strike.json`
- Create: `res://addons/turn_skill_system/data/skills/active/act_hero_whirlwind.json`
- Create: `res://addons/turn_skill_system/data/skills/active/act_ally_heal.json`
- Create: `res://addons/turn_skill_system/data/skills/aura/aur_ally_guard.json`
- Create: `res://addons/turn_skill_system/data/skills/active/act_boss_crush.json`
- Create: `res://addons/turn_skill_system/data/skills/active/act_boss_quake.json`
- Create: `res://addons/turn_skill_system/data/skills/active/act_minion_stab.json`
- Modify: `res://addons/turn_skill_system/data/skills/index.json`

- [ ] Step 1: 按 spec 创建技能 JSON
  - AOE 技能填 `cooldown_turns`：Hero=2，Boss=3
  - 治疗使用 `heal` effect（amount=35）
  - 光环范围改为 `ally_all`（全体友军），on_enter apply buff_dmg_reduce_20p
  - Boss：所有主动技能都有 cooldown（例如 crush=2，quake=4）；并新增无冷却普攻 `act_boss_basic`
  - 队友：新增无冷却普攻 `act_ally_basic`
- [ ] Step 2: 更新 skills/index.json 注册这些 skill
- [ ] Step 3: 运行现有 skill_validator/index_builder 测试（GUT）
- [ ] Step 4: Commit：
  - `git add ... && git commit -m "feat(content): add mini battle roster skills"`

---

## Task 8（GREEN）: demo_battle 改为 mini battle 配置并接入被动/光环

**Files:**
- Modify: `res://addons/turn_manager/demo/demo_battle.gd`

- [ ] Step 1: 按 spec 构造 2v2 单位，设置 stats（HP/MP/ATK/DEF/SPEED）初值与站位（ally x=0 / enemy x=2）
- [ ] Step 2: 在 bootstrap 中注册：
  - `passive_manager.register_unit_passives(hero, ["pas_hero_battle_haste"])`
  - `aura_manager.register_aura(ally, "aur_ally_guard")` 并 `refresh_all()`
- [ ] Step 3: 实现 AI 选择策略（按 6 节），并遵守 cooldown
  - Boss：若 quake/crush 都在冷却，必须退化为 `act_boss_basic`
  - Ally：治疗不需要时退化为 `act_ally_basic`
- [ ] Step 4: 手动运行 demo 验收：
  - 开战 hero 先手
  - AOE 不会连续回合释放（>=2）
  - 最终 battle_ended
- [ ] Step 5: Commit：
  - `git add ... && git commit -m "chore(demo): add mini battle 2v2 roster demo"`

---

## Task 9（可选）: 文档

**Files:**
- Modify: `res://addons/turn_manager/README.md`

- [ ] Step 1: 记录 mini battle roster 的 skill_id 列表与属性表（便于复用）
- [ ] Step 2: Commit：
  - `git add ... && git commit -m "docs: document mini battle roster"`

---

## Execution Notes
- 严格遵守：不改 SkillRuntime 固定 API；所有 buff/damage 走 OmniBuffAdapter；camp 仅 ally/enemy。
- 每个 Task 完成后都要 `git commit`（测试与实现分开，遵守 RED→GREEN）。
