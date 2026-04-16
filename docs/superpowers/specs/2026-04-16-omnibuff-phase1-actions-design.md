# OmniBuff Phase 1：Action 扩展（设计）

## 背景

Phase 1 的 Filters/Selectors 已完成并在 rpg_tests+Demo 中跑通。下一步按路线图进入 **Action 扩展**：在不引入脚本语言的前提下，用“白名单 action.kind”覆盖 MOBA 高频效果。

本设计以 **Demo-only** 为优先：可测、可回放、可在 Debug HUD 解释；并尽量保持对现有架构的低侵入。

---

## 目标（本轮 Phase 1 Action 全量）

在 `trigger.action.kind` 增加以下 action，并提供端到端覆盖（validators + tests + demo + HUD 输出）：

1) `ADD_SHIELD`：对目标追加护盾（SHIELD += value）
2) `HEAL`：对目标治疗（HP += value）
3) `DISPEL`：对目标驱散（复用 BuffCore.dispel_by_*）
4) `LIFESTEAL`：吸血（在 AFTER_DEAL 基于本次 final_damage 治疗攻击者）
5) `REFLECT_DAMAGE`：反伤（在 AFTER_TAKE 基于本次 final_damage 直接扣攻击者 HP；避免递归触发）

并保留现有 action：
- `ADD_BASE_DAMAGE` / `APPLY_BUFF` / `CHANCE_APPLY_BUFF`
- `SET_STAT_FINAL`
- `SET_SHIELD_TO_FINAL_DAMAGE`
- `DOT_*`

---

## 非目标（本轮不做）

- 复杂“公式/表达式 action”（例如 value=ATK*0.3），仍坚持常量或基于 ctx 的固定来源
- 递归伤害链（反伤触发再次触发反伤…）——本轮反伤采用“直接扣 HP”来避免
- 资源系统（mana/energy）、仇恨、距离等需要主游戏系统支撑的能力

---

## 数据协议（JSON Schema）

### 1) ADD_SHIELD / HEAL

```jsonc
{ "kind": "ADD_SHIELD", "value": 50.0 } // SHIELD += 50
{ "kind": "HEAL", "value": 30.0 }       // HP += 30
```

- `value` 必填，float，允许 0；负数视为非法（validators error）
- `scope`：支持 SELF/SOURCE/TARGET（复用现有 scope 解析）
- 推荐 phase：
  - HEAL：AFTER_DEAL / AFTER_TAKE / TURN_TICK（按事件类型）
  - ADD_SHIELD：BEFORE_TAKE / APPLY / AFTER_TAKE（按需求）

### 2) DISPEL

```jsonc
{ "kind":"DISPEL", "mode":"BY_TAG", "tag":"DEBUFF", "include_implicit": false }
{ "kind":"DISPEL", "mode":"BY_SOURCE", "source":"SOURCE" } // 驱散来自攻击者的效果
{ "kind":"DISPEL", "mode":"BY_TYPE", "buff_type":"EXPLICIT" }
```

字段：
- `mode`：`"BY_TAG" | "BY_SOURCE" | "BY_TYPE"`
- `tag`：当 mode=BY_TAG 必填（如 "DEBUFF"）
- `source`：当 mode=BY_SOURCE 必填，值为 `"SOURCE" | "TARGET"`（映射到实体 id）
- `buff_type`：当 mode=BY_TYPE 必填（如 "EXPLICIT"）
- `include_implicit`：可选，默认 false

语义：
- 复用 `BuffCore.dispel_by_tag/dispel_by_source/dispel_by_type`
- 仍受 `target_dispel_immunity_mask` 影响（这是既有规则）

### 3) LIFESTEAL

```jsonc
{ "kind":"LIFESTEAL", "ratio": 0.2 } // heal = ctx.final_damage * 0.2
```

字段：
- `ratio` 必填，float，范围 [0..1]（validators error if out of range）

语义：
- 推荐挂在 `DAMAGE/AFTER_DEAL`，scope=SOURCE（治疗攻击者）
- heal_amount = `ctx.final_damage * ratio`

### 4) REFLECT_DAMAGE

```jsonc
{ "kind":"REFLECT_DAMAGE", "ratio": 0.3 } // attacker HP -= ctx.final_damage*0.3
```

字段：
- `ratio` 必填，float，范围 [0..1]

语义（关键决策）：
- 推荐挂在 `DAMAGE/AFTER_TAKE`，scope=SOURCE（对攻击者生效）
- reflect_amount = `ctx.final_damage * ratio`
- **实现为直接修改 StatsComponent.HP（add_base）**，不走 DamagePipeline，避免递归触发与复杂的 tags/roll_key 处理

---

## 运行时设计（实现落点）

### 1) enums.action_kind
在 `data/base_demo/enums.json` 的 `action_kind` 白名单追加：
- ADD_SHIELD, HEAL, DISPEL, LIFESTEAL, REFLECT_DAMAGE

### 2) Listener payload 扩展（BuffCore 注册时解析）
在 `OmniEventIndex.Listener` 增加以下字段（默认值保证兼容）：
- `action_ratio: float`（用于 LIFESTEAL/REFLECT_DAMAGE）
- `action_dispel_mode: String`
- `action_dispel_tag: String`
- `action_dispel_buff_type: String`
- `action_dispel_source_scope: String`（"SOURCE"/"TARGET"）
- `action_include_implicit: bool`

并在 `BuffCore._register_triggers_for_instance()` 将 action dict 映射到上述字段。

### 3) action 执行（BuffCore.emit_event）
在 `match l.action_kind` 增加分支：
- ADD_SHIELD → `_add_shield_from_event(l, ctx)`
- HEAL → `_heal_from_event(l, ctx)`
- DISPEL → `_dispel_from_event(l, ctx)`
- LIFESTEAL → `_lifesteal_from_event(l, ctx)`
- REFLECT_DAMAGE → `_reflect_from_event(l, ctx)`

这些 helper 与现有 `_set_stat_final_from_event/_apply_buff_from_event` 一样通过 `ctx.meta.runtime` 获取 `stats_by_entity/buff_by_entity`。

---

## 测试与 Demo（验收）

### Tests（GUT）
新增 `tests/rpg/test_event_actions_phase1.gd` 覆盖：
- HEAL：受伤后 heal 恢复（HP 增加）
- ADD_SHIELD：加盾后下一次伤害先耗盾
- DISPEL：驱散 DEBUFF 后 DOT 实例也被清理（复用既有规则）
- LIFESTEAL：AFTER_DEAL 基于 ctx.final_damage 计算治疗
- REFLECT_DAMAGE：AFTER_TAKE 直接扣攻击者 HP，且不触发额外 DAMAGE 事件链

### Demo（buff_ui_demo）
新增 3~5 个 scenario：
- action_heal
- action_add_shield
- action_dispel
- action_lifesteal
- action_reflect

HUD 要求：
Listeners tab 能显示 action 摘要（kind + value/ratio + dispel 参数）。

---

## 验收标准

- [ ] validators 对新增 action 字段/范围做治理（缺字段给 hint）
- [ ] tests 全绿（新增文件 + 旧用例抽样）
- [ ] demo scenario 可复现并能用 HUD 解释触发链
- [ ] 不引入递归伤害/无限循环（反伤为 direct HP delta）

