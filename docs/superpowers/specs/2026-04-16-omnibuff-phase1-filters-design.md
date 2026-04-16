# OmniBuff Phase 1：Filters / Selectors 扩展设计

## 背景

Phase 0 已完成 Demo-only 的可观测性闭环（Scenario Runner + Debug HUD + dump/validate）。Phase 1 的目标是让 Buff 系统更“像 MOBA”：**策划能用数据更精确地描述触发条件**，而不是靠新增硬编码或写大量绕路 buff。

你已选择 Phase 1 优先做：**过滤器 / 选择器（filters/selectors）**。

---

## 目标（Phase 1 范围）

在 `buff_defs.json -> triggers[].filters` 增加一批高收益过滤器，并在运行时 EventIndex 里高效执行：

1) **命中/暴击类**
   - `require_hit`（已有）
   - `require_crit`（新增）：仅当 `ctx.crit==true` 才触发
2) **技能/伤害类别**
   - `skill_id`（新增）：仅当 `ctx.skill_id == filters.skill_id` 才触发
   - `damage_type_any`（新增）：仅当 `ctx.damage_type` 命中集合才触发（PHYSICAL/MAGIC/TRUE）
   - `element_any`（新增）：仅当 `ctx.element` 命中集合才触发（FIRE/ICE/…）
3) **护盾吸收（对 MOBA 很常见）**
   - `require_shield_absorbed`（新增）：仅当本次伤害发生护盾吸收（absorbed_shield > 0）才触发
   - `min_absorbed_shield`（新增）：仅当 absorbed_shield >= 阈值才触发
4) **伤害阈值**
   - `min_final_damage`（新增）：仅当 `ctx.final_damage >= 阈值` 才触发

并保持现有：
- `tag_mask_any`（已支持）
- `stat_threshold`（已支持最小版，基于 scope/stat/op/value）

---

## 非目标（Phase 1 不做）

- 阵营/单位类型/距离等需要“单位系统/空间系统”的过滤（后续可在主游戏层提供）
- 复杂表达式语言（Lua/DSL），仍坚持白名单字段 + 校验器治理
- 对每个 listener 输出“失败原因”解释（Phase 1.5 可在 HUD 中做）

---

## 数据协议（JSON Schema）

在 `triggers[].filters` 中新增字段（全部可选，未填表示不过滤）：

```jsonc
{
  "tag_mask_any": ["BUFF"],            // 已有
  "require_hit": true,                 // 已有

  "require_crit": true,                // 新增
  "skill_id": 1001,                    // 新增：int
  "damage_type_any": ["PHYSICAL"],     // 新增：enum array -> bitmask
  "element_any": ["FIRE","POISON"],    // 新增：enum array -> bitmask

  "require_shield_absorbed": true,     // 新增：bool
  "min_absorbed_shield": 10.0,         // 新增：float
  "min_final_damage": 1.0,             // 新增：float

  "stat_threshold": {                  // 已有
    "scope":"TARGET",
    "stat":"HP",
    "op":"LE",
    "value":50
  }
}
```

---

## 运行时设计（EventIndex / BuffCore）

### 1) Listener 字段扩展（紧凑可比对）
在 `OmniEventIndex.Listener` 增加：
- `filter_require_crit: bool`
- `filter_skill_id: int`（默认 -1）
- `filter_damage_type_mask_any: int`（默认 0，0=不过滤）
- `filter_element_mask_any: int`（默认 0）
- `filter_require_shield_absorbed: bool`
- `filter_min_absorbed_shield: float`（默认 0）
- `filter_min_final_damage: float`（默认 0）

### 2) 触发注册：从 JSON 解析到 Listener
`BuffCore._register_triggers_for_instance()`：
- 从 `filters` dict 读取上述字段
- 对 `damage_type_any/element_any` 用 `enums_rt.enum_int()` 映射为 bit index，再转成 bitmask

### 3) 事件触发：emit_event 里做快速过滤
在 `BuffCore.emit_event()` 的循环中，按顺序做 cheap checks（尽量早返回）：

1) tag_mask
2) require_hit / require_crit
3) skill_id（-1 跳过）
4) damage_type/element mask（mask==0 跳过）
5) shield absorbed / thresholds（读取 `ctx.get_meta("absorbed_shield")`，缺失视为 0）
6) min_final_damage（使用 ctx.final_damage）
7) stat_threshold（最贵，放最后；已有）

性能约束不变：只遍历 `listeners[key]` 子集，不允许遍历全 buff。

---

## DamageContext 数据来源（对接 DamagePipeline）

当前 `DamageContext` 已包含字段：
- `skill_id` / `damage_type` / `element`（目前是占位，默认值未赋）
- `crit`、`hit`（已在 resolve 中设置）
- `final_damage`（resolve+减伤+护盾吸收后可用）
- `absorbed_shield`（已通过 meta 写入）

Phase 1 需要最小补齐：
1) `deal_damage()` 增加可选参数（或通过 meta）写入：
   - `skill_id`（默认 -1）
   - `damage_type`（默认 enums.damage_type 的 0 = PHYSICAL 或 NONE，取决于枚举）
   - `element`（默认 NONE）
2) `deal_damage_with_tags()` 同步支持上述参数（或保持默认）

---

## 测试与 Demo 场景（验收方式）

### 新增/调整测试（建议最小集）
新增 `tests/rpg/test_event_filters_extended.gd`，覆盖：
- require_crit：设置 CRIT_RATE=1，断言触发；CRIT_RATE=0 断言不触发
- require_shield_absorbed：给 defender 加 shield，断言 only-if-absorbed 的触发行为
- min_final_damage：小伤害不触发，大伤害触发
- damage_type_any / element_any：为 damage_pipeline 传入 type/element，断言过滤正确

### Demo
在 `buff_ui_demo` 增加 1~2 个 scenario：
- “暴击才触发的 on-hit”
- “护盾吸收才触发的反应”
- “Boss 火焰免疫”：当 `element=FIRE` 时，本次伤害应被完全吸收（`final_damage=0`）

**Boss 火焰免疫推荐实现（不引入新 action.kind）：**
- 给 Boss（defender）挂一个永久 buff：`buff_boss_fire_immunity`
- 在该 buff 的 `triggers` 中注册：
  - `event_type=DAMAGE`, `event_phase=BEFORE_TAKE`, `scope=SELF`
  - `filters.element_any=["FIRE"]`
  - `action.kind=SET_STAT_FINAL`, `action.stat="SHIELD"`, `action.value=<very_large>`
- 由于护盾吸收发生在 APPLY 阶段，该 BEFORE_TAKE 的 `SET_STAT_FINAL(SHIELD=超大值)` 会确保 **火焰伤害被护盾完全吸收**，从而 `ctx.final_damage==0` 且 HP 不减少。

---

## 验收标准（Phase 1 Filters 完成态）

- [ ] filters 字段扩展 + validators 校验通过（未知字段报错/警告）
- [ ] emit_event 在不遍历全 buff 的前提下完成所有过滤判断
- [ ] 单测覆盖新增 filters 的正反例（命中/不命中）
- [ ] HUD 的 Listeners 输出中可看到新增 filters 的摘要（至少 require_crit / shield / min_final_damage）
