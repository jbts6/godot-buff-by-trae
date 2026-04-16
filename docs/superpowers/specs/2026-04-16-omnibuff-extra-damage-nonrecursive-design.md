# OmniBuff：追加伤害（不递归触发）设计

## 背景

你想实现一类被动：**每次造成伤害时，额外追加一次 xxx**，并且要求：
- 追加的伤害 **不会再次触发追加**（避免无限递归 / 指数爆炸）
- 适用于 multi-hit / multi-target（每次 deal_damage 都算一次“造成伤害”）

当前系统特性：
- 每次 `DamagePipeline.deal_damage()` 会触发完整 `DAMAGE/*` 事件链
- `BuffCore.emit_event()` 可以读写 ctx（含 meta）
- `tags_mask` 已作为 filters 基础设施存在

---

## 目标

在不引入脚本语言、不破坏现有事件/执行器骨架的前提下，提供一个可配置的“追加伤害”动作，并实现 **可靠的防递归机制**。

---

## 方案概览（推荐）

### 1) 防递归：使用 ctx.meta guard

约定一个 meta key：
- `ctx.meta["is_bonus_damage"] = true` 表示本次 damage 是“追加伤害”

然后在追加伤害触发器上加一个 filter：
- `filters.require_not_bonus_damage = true`

实现方式：
- 在 `BuffCore.emit_event` 的过滤链中，如果 listener 启用了 `require_not_bonus_damage`，则当 `ctx.get_meta("is_bonus_damage")==true` 时跳过。
- 在执行追加伤害动作时（见下文），调用 `DamagePipeline.deal_damage(...)` 前把 `is_bonus_damage` 写入 ctx（通过 meta 传递给新的 DamageContext），或者更直接：在 `deal_damage()` 创建的 ctx 上 set_meta。

> 解释：使用 meta guard 比 tags 更可靠，因为 tags 常常用于游戏语义（DOT/FIRE/BASIC_ATTACK），而 “bonus damage” 是引擎控制流语义。

### 2) 新增 action：`BONUS_DAMAGE`

配置形态（buff_defs.triggers[].action）：

```jsonc
{
  "kind": "BONUS_DAMAGE",
  "value": 5.0,
  "tags_mask_any": ["BONUS_DAMAGE"],  // 可选：写入新伤害的 tags（用于 UI/日志解释）
  "scope": "TARGET"                  // 可选：伤害目标（默认 TARGET）
}
```

语义：
- 在 `DAMAGE/AFTER_DEAL` 触发时，对指定目标追加一次“直接伤害”
- 默认：
  - 来源：当前 ctx.attacker_id
  - 目标：当前 ctx.defender_id（或 scope=TARGET）
  - base_damage：action.value
  - roll_key：沿用当前 roll_key + 一个固定偏移（例如 +10000），保证 deterministic 且与原段不冲突
- 追加伤害的 ctx 会带 `meta.is_bonus_damage=true`

### 3) 运行时依赖注入

因为 `BONUS_DAMAGE` 需要再次调用 `DamagePipeline.deal_damage`，必须拿到 pipeline 与 ds。
当前已有 runtime 约定：`ctx.meta["runtime"] = {stats_by_entity, buff_by_entity}`

本轮扩展 runtime（仅用于事件动作）：
- `runtime["pipeline"] = OmniDamagePipeline`
- `runtime["ds"] = OmniCompiledDataset`
- `runtime["enums_rt"] = OmniEnumsRuntime`
- `runtime["turn_index"] = int`（可选，若 ctx.meta 已有 turn_index 则优先用 meta）

BattleExecutor 在调用 `deal_damage` 前确保 runtime 注入这些字段。

---

## filters 扩展

新增：
- `require_not_bonus_damage: bool`（默认 false）

当该 filter 为 true 时：
- 如果 `ctx.meta["is_bonus_damage"]==true`，则该 listener 不触发。

---

## validators 扩展（schema 治理）

- `filters` 白名单加入 `require_not_bonus_damage`
- `action` 白名单加入 `BONUS_DAMAGE` 的字段：
  - `tags_mask_any`（可选数组）
  - `scope`（可选，默认 TARGET）
  - `value` 必须 >0

---

## 测试与 Demo（验收）

### Tests
新增 `test_bonus_damage_nonrecursive.gd`：

用例：
1) defender 受到一次攻击（base_damage=10）
2) attacker 身上有 buff：`DAMAGE/AFTER_DEAL` → `BONUS_DAMAGE(value=3)`，并带 `require_not_bonus_damage=true`
3) 断言：
   - replay.damage_traces 新增 2 条（原伤害 + 追加伤害）
   - 且不会出现第 3 条（追加不再触发追加）

### Demo
在 `buff_ui_demo` 增加 scenario：`bonus_damage_nonrecursive`
- 展示两条 DamageTrace，第二条带 tags_mask(BONUS_DAMAGE) 或日志标记

---

## 验收标准

- [ ] 追加伤害能在 AFTER_DEAL 正常触发
- [ ] 追加伤害不会递归触发追加（严格 2 条 trace）
- [ ] 多段/多目标时每段都可触发一次追加（仍不递归）

