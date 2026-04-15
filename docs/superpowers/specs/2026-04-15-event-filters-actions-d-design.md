# D（事件 filters/actions 丰富化）设计（真实战斗驱动：命中后碎盾）

## 目标

以一个真实战斗需求驱动 D 的第一轮扩展，并保证可回归：

> **命中后击碎护盾，先碎盾再结算本次伤害（破盾穿透）。**

实现要求：
- 不能写死特例：要以可复用的 filter/action 能力实现
- 保持性能硬约束：事件触发只遍历 `EventIndex.listeners[key]` 子集（禁止遍历全 Buff）

## 本轮范围（最小集）

### 新增 filters

1) `require_hit: bool`
- 为 true 时仅当 `ctx.hit == true` 才触发（避免 miss 也碎盾）。

2) `stat_threshold: { scope, stat, op, value }`
- 在指定 scope 的实体上读取 `StatsComponent.get_final(stat)` 并做阈值比较。
- `scope`: `SELF|SOURCE|TARGET`
- `op`: `GT|GE|LT|LE`
- 用于碎盾：`TARGET.SHIELD > 0`

### 新增 action

3) `SET_STAT_FINAL`
- 语义：将某 stat 的“最终值”设为指定值（通过调整 base 实现）。
- 实现方式（不访问 modifiers 细节）：
  - `current = target.get_final(stat_id)`
  - `delta = desired - current`
  - `target.add_base(stat_id, delta)`

## 事件挂载阶段（关键）

碎盾需要“在护盾吸收前生效”，因此挂在：
- `event_type = DAMAGE`
- `event_phase = APPLY`
- `scope = TARGET`

因为当前 `DamagePipeline` 在 `APPLY` 事件触发后才执行：
1) 读 SHIELD 进行吸收
2) 扣 HP

所以在 `APPLY` 阶段把 SHIELD 设为 0，就能保证“先碎盾再结算本次伤害”。

## 数据样例（rpg_tests）

新增一个测试用 buff（挂在攻击者身上）：

```json
{
  "id": "buff_on_hit_shatter_shield",
  "name": "命中后碎盾（APPLY前置）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [],
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "APPLY",
      "scope": "TARGET",
      "filters": {
        "tag_mask_any": ["BUFF"],
        "require_hit": true,
        "stat_threshold": { "scope": "TARGET", "stat": "SHIELD", "op": "GT", "value": 0.0 }
      },
      "action": { "kind": "SET_STAT_FINAL", "stat": "SHIELD", "value": 0.0 }
    }
  ]
}
```

## 校验/兼容

- `validators.gd`：允许新增 filters 字段 `require_hit`、`stat_threshold`（否则 strict 模式会报未知字段）
- `enums.json`：`action_kind` 增加 `SET_STAT_FINAL`（否则 strict 模式会报 action_kind 不存在）

## 单测（必须）

新增 GUT 用例：`test_event_shatter_shield_before_apply.gd`

断言：
1) baseline：defender 有 `SHIELD=50`，无碎盾 buff → 本次伤害优先被盾吸收，HP 不变，SHIELD 下降  
2) 有碎盾 buff：同样盾值 → 本次伤害应直接扣 HP，且 SHIELD 在本次结算后为 0

## 验收标准

- 新增 filter/action 有专门单测覆盖
- 现有 A/B/C 与整回合集成测试不回归

