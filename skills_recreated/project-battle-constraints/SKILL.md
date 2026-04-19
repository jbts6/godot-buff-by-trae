---
name: project-battle-constraints
description: 本项目战斗/技能系统（turn_skill_system + omnibuff）集成硬约束。只要用户要改技能系统、伤害/BUFF/模拟结算、事件口径、技能 JSON（act_/pas_/aur_），就必须启用本 skill；强制所有结算通过 OmniBuffAdapter，camp 只允许 ally/enemy，且不得改动 SkillRuntime 固定 API。
---

# 项目战斗/技能系统约束（AI Agent）

此 skill 仅当你要修改/新增以下内容时必须启用：
- `addons/turn_skill_system/**`
- `addons/omnibuff/**`（尤其是 runtime 与集成逻辑）

## 1) 必读：完整约束
在开始任何代码改动前，先阅读并遵守：
- `references/constraints.md`

## 2) 最重要的四条（摘要）
1. **Unit 契约**：单位必须有 `entity_id/camp/cell/stats/buffs`，且 `camp` **只允许** `"ally"` / `"enemy"`。
2. **SkillRuntime 固定 API 不得改名/改语义**：`cast/cast_to_unit/cast_to_cell/simulate_cast`。
3. **所有结算必须通过 OmniBuffAdapter**：damage 必走 DamagePipeline；buff 必走 BuffCore；simulate 不落地。
4. **事件口径统一**：事件名以 `EventNames` 为准，派发与捕获用 `BattleEventBus`，上层优先消费 `events[]`。

## 3) 建议测试用例（用于评估本 skill 是否生效）
**用例 1：**
> “我想新增一个 skill effect，会影响伤害结算，但必须走 OmniBuffAdapter，并且补齐 GUT 测试（严格双提交 TDD）。”

**用例 2：**
> “我想修改技能 JSON schema/校验器/索引生成，确保 act_/pas_/aur_ 前缀与 index.json 懒加载仍可用，并补测试。”

