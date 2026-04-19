---
name: project-battle-constraints
description: 本项目战斗/技能系统（turn_skill_system + omnibuff）集成硬约束：Unit 契约、camp 限制、SkillRuntime 固定 API、所有结算必须通过 OmniBuffAdapter、事件口径与技能 JSON 规范。
---

# 项目战斗/技能系统约束（AI Agent）

此 skill 仅当你要修改/新增以下内容时必须启用：
- `addons/turn_skill_system/**`
- `addons/omnibuff/**`（尤其是 runtime 与集成逻辑）

---

## 内容

> 下文为完整约束正文（同步自 `docs/SKILL_PROJECT_BATTLE.md`）。

---

# SKILL_PROJECT_BATTLE — 战斗/技能系统项目约束（AI Agent）

> 本文档是 AI Agent 的**项目特定硬约束**。  
> 仅当你要修改/新增以下内容时必须启用：  
> - `addons/turn_skill_system/**`  
> - `addons/omnibuff/**`（尤其是 runtime 与集成逻辑）  
>
> 违反任意 “MUST/禁止” 条款即视为不合格产出。

**适用版本：Godot 4.7**  
**语言：GDScript**  
**测试：GUT（headless）**  

---

## 1) Unit 契约（强制）

任何进入技能/战斗系统的单位对象（Node / RefCounted / Object）必须具备字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `entity_id` | `int` | 全局唯一实体 ID |
| `camp` | `String` | **只允许 `"ally"` / `"enemy"`** |
| `cell` | `Vector2i` | 3×3 格子坐标，范围 `0..2` |
| `stats` | OmniBuff StatsComponent | 伤害/治疗读取与写回 |
| `buffs` | OmniBuff BuffCore | apply/remove buff |

> 禁止引入新的 camp 取值（如 `neutral`），除非先更新所有 targeting/规则与测试。

---

## 2) turn_skill_system 的对外 API（强制，不得改名）

`SkillRuntime` 对外入口是固定 API，禁止改名/改语义：
- `SkillRuntime.cast(skill_id, caster, primary_cell=null, extra={})`
- `SkillRuntime.cast_to_unit(skill_id, caster, target, extra={})`
- `SkillRuntime.cast_to_cell(skill_id, caster, cell, extra={})`
- `SkillRuntime.simulate_cast(skill_id, caster, primary_cell=null, extra={})`

任何变更需先写 RED 用例锁定新行为，并保证老行为兼容（除非明确 breaking change）。

---

## 3) OmniBuff 集成硬规则（强制）

### 3.1 所有结算必须通过 Adapter
禁止在 effect handler 或 runtime 其它地方绕开 adapter 直接操作：
- 禁止直接改 `stats`（除非这是 adapter 内部实现）
- 禁止直接调用 `BuffCore`（除非通过 adapter 的统一入口）

### 3.2 Damage（强制）
- `damage` 必须走 `OmniBuff.DamagePipeline`
  - 优先：`deal_damage`
  - 兜底：`deal_damage_v1`
- 参数映射必须稳定（damage_type/element/tags_mask/roll_key/turn_index 等）
- adapter 返回应包含可追溯 meta（便于 tests 断言“确实走了 pipeline 且映射正确”）

### 3.3 Buff（强制）
- `apply_buff/remove_buff` 必须走 `OmniBuff.BuffCore`
- remove 必须支持 remove_scope（例如 ALL）

### 3.4 Simulation（强制）
`simulate_cast` 必须满足：
- **不落地**：不真实修改 HP，不 apply/remove buff
- 返回可消费的预测结构（如 `predicted_deltas`）

---

## 4) 事件口径（强制）

### 4.1 事件名
事件名以 `EventNames` 为准（字符串常量）。禁止随意拼写 event_type 字符串。

### 4.2 事件派发/捕获
- 统一使用 `BattleEventBus` 派发与捕获
- `cast()` 返回必须携带 `events[]`（用于回放/表现/AI 特征）
- 表现层/AI 优先消费 `events[]`，而不是直接读 `effects[]` 或内部对象状态

---

## 5) 技能 JSON 约束（turn_skill_system）

### 5.1 目录结构（强制）
```
addons/turn_skill_system/data/skills/
  index.json
  active/*.json
  passive/*.json
  aura/*.json
```

### 5.2 ID 与文件名（强制）
- active：`act_*`
- passive：`pas_*`
- aura：`aur_*`
- 文件名必须与 id 对齐：`<id>.json`

### 5.3 tags（约束）
- tags 建议全大写（例如 `["BUFF","BASIC_ATTACK"]`）
- 禁止大小写混用（同一个 tag 不允许出现 `buff` 与 `BUFF` 两种写法）

---

## 6) 测试约束（项目特定）

当修改 `turn_skill_system` 或其与 `omnibuff` 的集成点时，必须增加/更新 GUT 用例覆盖：
- SkillRuntime 成功/失败返回结构
- DamagePipeline 走通与参数透传
- simulate 不落地
- 解析期兼容（必要时加 preload 编译守卫测试）

---

## 7) Agent 交付自检（项目特定）
- [ ] 未改动 SkillRuntime 固定 API 的名字与语义（或已写明 breaking 并有完整测试迁移）
- [ ] 未绕开 OmniBuffAdapter（所有伤害/buff/治疗入口统一）
- [ ] `camp` 只出现 `"ally"` / `"enemy"`
- [ ] skills JSON 的 id/文件名/prefix/tag 大小写符合规范
- [ ] 相关 GUT tests 全绿

