# OmniBuff 策划配置指南

> 本文档面向游戏策划，提供 OmniBuff Buff 系统的配置参考。
> 最后更新：2026-04-28

---

## 一、配方索引："我想实现 XXX 效果，应该怎么配？"

### 1. 固定值加成（如 ATK+20）

```json
{
  "id": "buff_atk_flat_20",
  "name": "ATK+20",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 20.0 }
  ],
  "triggers": []
}
```

**要点**：`op: "ADD"` + `phase: "FLAT"` = 固定值加成。`value` 为正数加、负数减。

### 2. 百分比加成（如 ATK+5%）

```json
{
  "effects": [
    { "kind": "modifier", "stat": "ATK", "op": "MUL", "phase": "PERCENT", "priority": 110, "value": 0.05 }
  ]
}
```

**要点**：`op: "MUL"` + `phase: "PERCENT"` = 百分比乘算。`value: 0.05` 表示 5%。计算公式：`final = (base + flat_sum) × Π(1 + pct_value)`。

**多层百分比**：用 `layer` 字段控制乘算顺序。`layer` 越大越后乘（越强力）。例如：
- `layer: 0` → 基础百分比（如"攻击力+10%"）
- `layer: 1` → 总百分比（如"总攻击力+20%"）

### 3. 回合制限时 Buff（如 ATK+10 持续 3 回合）

```json
{
  "duration": { "type": "TURNS", "turns": 3, "tick_phase": "TURN_END" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "GLOBAL" }
}
```

**要点**：
- `tick_phase: "TURN_END"` → 回合结束时减 1；`"TURN_START"` → 回合开始时减 1
- `refresh_policy: "RESET_TO_MAX"` → 重复施加时重置回合数；`"NONE"` → 不刷新

### 4. 可叠层 Buff（如 ATK+10/层，最多 3 层）

```json
{
  "stack": { "mode": "ADD_STACK", "max_stack": 3, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "GLOBAL" }
}
```

**要点**：`mode: "ADD_STACK"` → 每次施加增加 1 层（效果叠加）。`max_stack` 为层数上限。

### 5. 按来源独立叠层（如每来源 DEF+5，最多 2 层/来源）

```json
{
  "stack": { "mode": "ADD_STACK", "max_stack": 2, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "BY_SOURCE_INSTANCE" }
}
```

**要点**：`ownership_mode: "BY_SOURCE_INSTANCE"` → 不同来源各自独立计数叠层。

### 6. DOT 持续伤害（如灼烧 3 回合，每回合 30%ATK 伤害）

```json
{
  "id": "buff_dot_fire_3t",
  "tags": ["DEBUFF", "DOT", "FIRE"],
  "duration": { "type": "TURNS", "turns": 3, "tick_phase": "TURN_START" },
  "stack": { "mode": "ADD_STACK", "max_stack": 99, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "BY_SOURCE_INSTANCE" },
  "dot": {
    "tick_phase": "TURN_START",
    "element": "FIRE",
    "base_ratio": 0.3,
    "read_source_stat": "ATK"
  },
  "effects": [],
  "triggers": []
}
```

**要点**：
- 必须包含 `dot` 子结构，且 `tags` 中应包含 `"DOT"`
- `base_ratio` × `read_source_stat` = 每跳伤害
- `ownership_mode: "BY_SOURCE_INSTANCE"` → 不同来源的 DOT 独立实例

### 7. 命中后给目标挂 DOT

```json
{
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "AFTER_DEAL",
      "scope": "TARGET",
      "filters": { "tag_mask_any": ["BUFF"], "require_hit": true },
      "action": { "kind": "APPLY_BUFF", "buff_id": "buff_dot_fire_3t" }
    }
  ]
}
```

**要点**：`scope: "TARGET"` → 作用于目标；`require_hit: true` → 仅命中时触发。

### 8. 伤害前增加基础伤害（如普攻额外 +5）

```json
{
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "BEFORE_DEAL",
      "scope": "SELF",
      "filters": { "tag_mask_any": ["BUFF"], "require_hit": true },
      "action": { "kind": "ADD_BASE_DAMAGE", "value": 5.0 }
    }
  ]
}
```

### 9. 概率触发（如 50% 概率挂 DOT）

```json
{
  "action": { "kind": "CHANCE_APPLY_BUFF", "chance": 0.5, "buff_id": "buff_dot_fire_3t" }
}
```

**要点**：`chance` 为 0~1 的浮点数。概率判定使用确定性 RNG，同回合内结果一致。

### 10. 吸血（如造成伤害后回复 20% 最终伤害的 HP）

```json
{
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "AFTER_DEAL",
      "scope": "SELF",
      "filters": { "require_hit": true },
      "action": { "kind": "LIFESTEAL", "ratio": 0.2 }
    }
  ]
}
```

### 11. 反伤（如受到伤害后反弹 30% 给攻击者）

```json
{
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "AFTER_TAKE",
      "scope": "SOURCE",
      "filters": { "require_hit": true },
      "action": { "kind": "REFLECT_DAMAGE", "ratio": 0.3 }
    }
  ]
}
```

**要点**：`scope: "SOURCE"` → 作用于伤害来源（攻击者）。反伤不会递归触发伤害事件。

### 12. 护盾（受到伤害前加盾）

```json
{
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "BEFORE_TAKE",
      "scope": "SELF",
      "filters": { "require_hit": true },
      "action": { "kind": "ADD_SHIELD", "value": 50.0 }
    }
  ]
}
```

### 13. 驱散（如受击后清除自身 DEBUFF）

```json
{
  "action": { "kind": "DISPEL", "mode": "BY_TAG", "tag": "DEBUFF", "include_implicit": false }
}
```

**驱散模式**：
- `mode: "ALL"` → 驱散所有 Buff
- `mode: "BY_TAG"` → 按 tag 驱散（需指定 `tag`）
- `mode: "BY_SOURCE"` → 按来源驱散
- `mode: "BY_TYPE"` → 按 buff_type 驱散

### 14. 条件激活（如 HP≤50% 时 ATK+10）

```json
{
  "conditions": [
    { "condition_type": "STAT_THRESHOLD", "stat": "HP", "op": "LE", "value": 50.0 }
  ]
}
```

**要点**：条件不满足时 Buff 挂着但不生效（`active=false`），效果不应用。

### 15. 不可驱散 Buff

```json
{
  "dispel": { "dispellable": false }
}
```

### 16. 禁止逃跑（指令拦截）

```json
{
  "triggers": [
    {
      "event_type": "COMMAND",
      "event_phase": "CMD_BEFORE",
      "scope": "SELF",
      "filters": { "command_kind_any": ["ESCAPE"] },
      "action": { "kind": "CANCEL_COMMAND" }
    }
  ]
}
```

### 17. 元素免疫（如 FIRE 元素伤害免疫）

```json
{
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "APPLY",
      "scope": "SELF",
      "filters": { "element_any": ["FIRE"] },
      "action": { "kind": "SET_SHIELD_TO_FINAL_DAMAGE" }
    }
  ]
}
```

**要点**：`SET_SHIELD_TO_FINAL_DAMAGE` → 将护盾设为等于最终伤害值，等效于全额吸收。

### 18. 追加伤害（Bonus Damage，不递归）

```json
{
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "AFTER_DEAL",
      "scope": "TARGET",
      "filters": { "require_hit": true, "require_not_bonus_damage": true },
      "action": { "kind": "BONUS_DAMAGE", "value": 3.0, "tags_mask_any": ["BONUS_DAMAGE"], "scope": "TARGET" }
    }
  ]
}
```

**要点**：`require_not_bonus_damage: true` → 防止追加伤害递归触发自身。

---

## 二、常见错误排查表

| 错误现象 | 可能原因 | 解决方法 |
|----------|----------|----------|
| Buff 施加后属性没变化 | `effects` 为空或 `stat` 名拼写错误 | 检查 `stat` 是否与 `stat_defs.json` 中的 `id` 完全一致（区分大小写） |
| 百分比加成没生效 | `op` 写成了 `"ADD"` 而非 `"MUL"`，或 `phase` 不是 `"PERCENT"` | 百分比加成必须 `op: "MUL"` + `phase: "PERCENT"` |
| Buff 到期不消失 | `duration.type` 写成了 `"PERMANENT"` | 限时 Buff 需设置 `"TURNS"` 并指定 `turns` |
| 叠层不生效 | `stack.mode` 为 `"REPLACE"` 而非 `"ADD_STACK"` | 可叠层 Buff 必须用 `"ADD_STACK"` |
| 事件触发不执行 | `filters.tag_mask_any` 中的 tag 名不在 `enums.json` 的 `tags` 中 | 检查 tag 名是否与 `enums.json` 中定义的 `id` 一致 |
| 事件触发两次 | `scope` 设置错误导致攻击者和防守者都触发 | 确认 `scope` 是 `"SELF"` / `"TARGET"` / `"SOURCE"` 中的正确值 |
| DOT 伤害为 0 | `dot.base_ratio` 为 0 或 `read_source_stat` 对应的属性为 0 | 检查 `base_ratio` 和 `read_source_stat` 配置 |
| 驱散不了 Buff | `buff_type` 为 `"PASSIVE"` 或设置了 `dispel.dispellable: false` | 默认驱散只影响 `EXPLICIT` 类型；需 `include_implicit: true` 才能驱散 `IMPLICIT`/`PASSIVE` |
| 条件 Buff 不激活 | `condition_type` 值不在 `enums.json` 的 `condition_type` 枚举中 | 检查 `condition_type` 是否为 `STAT_THRESHOLD` / `EQUIP_SET_COUNT_GE` / `HAS_TAG` / `STAT_GE` |
| 编译报错 "unknown field" | JSON 中有未定义的字段 | 严格模式下未知字段会报错；检查拼写或切换到 lenient 模式 |
| Buff 施加后属性反而降低 | `value` 为负数 | 确认 `value` 的正负号是否符合预期 |
| OVERRIDE 不生效 | 两个同优先级 OVERRIDE 冲突 | `priority` 越大越优先；同优先级后施加的胜出 |

---

## 三、枚举值中文速查表

### op_type（运算类型）

| 值 | 含义 | 说明 |
|----|------|------|
| ADD | 加法 | 固定值加减，如 ATK+20 |
| MUL | 乘法 | 百分比乘算，如 ATK+5% |
| OVERRIDE | 覆盖 | 直接设定最终值，按 priority 裁决 |
| CLAMP | 钳制 | 限制数值范围 |
| FORMULA | 公式 | 表达式计算（高级用法） |

### apply_phase（应用阶段）

| 值 | 含义 | 计算顺序 |
|----|------|----------|
| BASE | 基础值 | 1（最先） |
| CONVERT | 转换 | 2 |
| FLAT | 平铺加成 | 3 |
| PERCENT | 百分比乘算 | 4 |
| FINAL | 最终值 | 5 |
| CLAMP | 钳制 | 6（最后） |

### duration_type（持续类型）

| 值 | 含义 | 说明 |
|----|------|------|
| PERMANENT | 永久 | 不会自动消失 |
| TURNS | 回合制 | 指定回合数后消失 |
| UNTIL_TURN_END | 直到回合结束 | 当回合结束时消失 |
| CHARGES | 充能次数 | 使用指定次数后消失 |
| WHILE_CONDITION | 条件维持 | 条件不满足时挂起/移除 |

### stack_mode（叠层模式）

| 值 | 含义 | 说明 |
|----|------|------|
| REPLACE | 替换 | 重复施加只保留一个 |
| ADD_STACK | 叠层 | 每次施加增加层数 |
| MULTI_INSTANCE | 多实例 | 每次施加创建独立实例 |

### refresh_policy（刷新策略）

| 值 | 含义 | 说明 |
|----|------|------|
| RESET_TO_MAX | 重置到最大 | 重复施加时重置剩余回合 |
| KEEP_MAX | 保留最大值 | 取当前和重置后的较大值 |
| NONE | 不刷新 | 不重置剩余回合 |

### buff_type（Buff 类型）

| 值 | 含义 | 驱散规则 |
|----|------|----------|
| EXPLICIT | 显式 | 可被驱散 |
| IMPLICIT | 隐式 | 需 `include_implicit: true` 才可驱散 |
| PASSIVE | 被动 | 需 `include_implicit: true` 才可驱散 |
| AURA | 光环 | 需 `include_implicit: true` 才可驱散 |

### event_type（事件类型）

| 值 | 含义 | 触发时机 |
|----|------|----------|
| DAMAGE | 伤害事件 | 伤害结算流程中 |
| TURN_TICK | 回合事件 | 回合开始/结束时 |
| BUFF_APPLY | Buff 施加 | Buff 被施加时 |
| BUFF_REMOVE | Buff 移除 | Buff 被移除时 |
| DEATH | 死亡事件 | 实体死亡时 |
| COMMAND | 指令事件 | 执行战斗指令时 |
| LIFE | 生命事件 | 死亡/复活时 |

### event_phase（事件阶段）

| 值 | 含义 | 所属事件 |
|----|------|----------|
| BUILD | 构建 | DAMAGE |
| BEFORE_DEAL | 攻击前 | DAMAGE（攻击者侧） |
| BEFORE_TAKE | 受击前 | DAMAGE（防守者侧） |
| RESOLVE | 结算 | DAMAGE（双方） |
| APPLY | 应用 | DAMAGE |
| AFTER_DEAL | 攻击后 | DAMAGE（攻击者侧） |
| AFTER_TAKE | 受击后 | DAMAGE（防守者侧） |
| CMD_BEFORE | 指令前 | COMMAND |
| CMD_AFTER | 指令后 | COMMAND |
| DEATH | 死亡 | LIFE |
| REVIVE | 复活 | LIFE |

### damage_type（伤害类型）

| 值 | 含义 |
|----|------|
| PHYSICAL | 物理伤害 |
| MAGIC | 魔法伤害 |
| TRUE | 真实伤害 |

### element（元素类型）

| 值 | 含义 |
|----|------|
| NONE | 无元素 |
| FIRE | 火 |
| ICE | 冰 |
| LIGHTNING | 雷 |
| POISON | 毒 |

### condition_type（条件类型）

| 值 | 含义 | 必需字段 |
|----|------|----------|
| STAT_THRESHOLD | 属性阈值 | `stat`, `op`, `value` |
| EQUIP_SET_COUNT_GE | 装备套装数≥ | `set_id`, `count` |
| HAS_TAG | 拥有标签 | `tag` |
| STAT_GE | 属性≥ | `stat`, `value` |

### ownership_mode（归属模式）

| 值 | 含义 | 说明 |
|----|------|------|
| GLOBAL | 全局 | 同 id 只有一个实例 |
| BY_SOURCE | 按来源 | 同来源合并，不同来源独立 |
| BY_SOURCE_INSTANCE | 按来源实例 | 每次施加都创建独立实例 |

### action_kind（动作类型）

| 值 | 含义 | 必需参数 |
|----|------|----------|
| ADD_BASE_DAMAGE | 增加基础伤害 | `value` |
| APPLY_BUFF | 施加 Buff | `buff_id` |
| CHANCE_APPLY_BUFF | 概率施加 Buff | `chance`, `buff_id` |
| SET_STAT_FINAL | 设置属性最终值 | `stat`, `value` |
| SET_SHIELD_TO_FINAL_DAMAGE | 护盾=最终伤害 | （无） |
| ADD_SHIELD | 增加护盾 | `value` |
| HEAL | 治疗 | `value` |
| DISPEL | 驱散 | `mode` |
| LIFESTEAL | 吸血 | `ratio` |
| REFLECT_DAMAGE | 反伤 | `ratio` |
| CANCEL_COMMAND | 取消指令 | （无） |
| BONUS_DAMAGE | 追加伤害 | `value` 或 `ratio` 或 `expr` |
| ADD_STACKS | 增加层数 | `buff_id`, `delta` |
| SET_STACKS | 设置层数 | `buff_id`, `value` |
| DOT_MUL_STACKS | DOT层数乘算 | `dot_buff_id`, `value` |
| DOT_ADD_STACKS | DOT层数加减 | `dot_buff_id`, `value` |
| DOT_SET_STACKS | DOT层数设置 | `dot_buff_id`, `value` |
| DOT_CLEAR | 清除DOT | `dot_tags_mask_any` |

### tags（标签）

| ID | code | 含义 |
|----|------|------|
| BUFF | 1 | 增益 |
| DEBUFF | 2 | 减益 |
| DOT | 3 | 持续伤害 |
| FIRE | 4 | 火属性 |
| EQUIP | 5 | 装备 |
| SET_BONUS | 6 | 套装效果 |
| POISON | 7 | 毒属性 |
| BASIC_ATTACK | 8 | 普通攻击 |
| BONUS_DAMAGE | 9 | 追加伤害 |

---

## 四、伤害管线阶段流程

```
build → before_deal → before_take → resolve → apply → after_deal → after_take → death
          (攻击者)      (防守者)     (双方)           (攻击者)     (防守者)
```

| 阶段 | 侧 | 可执行操作 |
|------|-----|-----------|
| BUILD | — | 修改 base_damage |
| BEFORE_DEAL | 攻击者 | ADD_BASE_DAMAGE, APPLY_BUFF 等 |
| BEFORE_TAKE | 防守者 | ADD_SHIELD, SET_STAT_FINAL 等 |
| RESOLVE | 双方 | 读取 final_damage |
| APPLY | — | SET_SHIELD_TO_FINAL_DAMAGE（免疫） |
| AFTER_DEAL | 攻击者 | LIFESTEAL, APPLY_BUFF（挂DOT） |
| AFTER_TAKE | 防守者 | HEAL, DISPEL, REFLECT_DAMAGE |
| DEATH | — | HEAL（击杀回复）, DISPEL（复活清debuff） |

---

## 五、Scenario JSON 测试格式

可通过 JSON 文件定义自动化测试场景：

```json
{
  "id": "test_atk_buff",
  "title": "ATK Buff 增加伤害",
  "dataset": "rpg_tests",
  "setup": [
    {"entity_id": 101, "base_stats": {"HP": 100, "ATK": 10, "DEF": 5}},
    {"entity_id": 202, "base_stats": {"HP": 100, "ATK": 5, "DEF": 5}}
  ],
  "steps": [
    {"action": "apply_buff", "entity_id": 101, "buff_id": "buff_atk_flat_20", "source_entity_id": 101},
    {"action": "deal_damage", "attacker_id": 101, "defender_id": 202, "base_damage": 20.0},
    {"action": "turn_end", "entity_ids": [101, 202]},
    {"action": "turn_start", "entity_ids": [101, 202]}
  ],
  "assertions": [
    {"path": "entity.202.stat.HP", "op": "lt", "value": 100},
    {"path": "entity.202.stat.HP", "op": "gt", "value": 0}
  ]
}
```

**支持的 step action**：`apply_buff`, `deal_damage`, `turn_end`, `turn_start`, `add_base`

**支持的 assertion op**：`eq`, `ne`, `gt`, `lt`, `ge`, `le`

**支持的 assertion path**：`entity.{eid}.stat.{name}`, `entity.{eid}.buff_count`
