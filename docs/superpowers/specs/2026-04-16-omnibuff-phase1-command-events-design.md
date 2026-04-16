# OmniBuff Phase 1：回合制 Command 事件域扩展（设计）

## 背景

你的战斗是**纯回合制、无移动**，玩家指令只有：
- 攻击（你设定为“普攻技能”的一种）
- 释放技能
- 使用道具
- 防御
- 逃跑

且你希望：**这些指令都能被 Buff 监听/修改**（例如普攻加成、禁止逃跑、使用道具后回血、进入防御状态等）。

同时你确认：**普攻也统一建模为 Skill**（有多个普攻 skill_id，都属于“普攻”，应吃“普攻加成”）。

---

## 目标

在不改动现有 `DAMAGE` 事件骨架的前提下，新增一个“战斗回合指令”事件域：

- `event_type = COMMAND`
- `event_phase = CMD_BEFORE | CMD_AFTER`

并提供：
1) **filters**：可按 `command_kind / skill_id / item_id / tags_mask_any` 过滤  
2) **actions**：可对指令本身产生效果（例如设置 ctx.cancel=true，或仅做附带动作）  
3) **可观测性**：在 Debug HUD 中可看见 COMMAND listeners 与最近一次命中列表

---

## 非目标（本轮不做）

- 不引入移动相关事件（你战斗中无移动）
- 不实现“完整技能系统”（目前 skill_defs 在 rpg_tests 仅是占位）
- 不引入脚本/表达式语言（仍坚持白名单 + validators）

---

## 事件域协议

### 1) enums 扩展

在 `data/base_demo/enums.json`：
- `event_type` 增加：`COMMAND`
- `event_phase` 增加：`CMD_BEFORE`, `CMD_AFTER`

> 注意：EventIndex 的 key 计算依赖 `phase_int`，因此 `PHASE_COUNT` 需要能覆盖新增 phase（当前为 16，新增后应上调并保持兼容）。

### 2) CommandContext（新 ctx 类型）

新增 `CommandContext`（RefCounted），字段：
- `actor_id: int`
- `command_kind: String`  
  允许值：`ATTACK | CAST_SKILL | USE_ITEM | DEFEND | ESCAPE`
- `skill_id: int`（当 ATTACK/CAST_SKILL 时有效，默认 -1）
- `item_id: int`（当 USE_ITEM 时有效，默认 -1）
- `targets: PackedInt32Array`（稳定顺序：entity_id 升序）
- `tags_mask: int`（bitmask，用于 filters.tag_mask_any；例如 BASIC_ATTACK）

以及控制流字段（Phase 1 最小）：
- `cancel: bool = false`：当 `CMD_BEFORE` 被某些 buff 设置为 true，则战斗系统应跳过实际指令执行（并可回放/提示）

### 3) 普攻分类（BASIC_ATTACK）

你会有多个普攻技能，但都属于“普攻”，建议用 **skill_tags** 表达：
- 在 `skill_defs.json` 为普攻技能添加 tag：`BASIC_ATTACK`
- Battle 系统构建 CommandContext 时，将该 tag 写入 `ctx.tags_mask`

这样：
- “普攻加成”可写成 `DAMAGE/BEFORE_DEAL` + `filters.tag_mask_any=["BASIC_ATTACK"]`（对伤害生效）
- “普攻触发器”也可写成 `COMMAND/CMD_AFTER` + `filters.tag_mask_any=["BASIC_ATTACK"]`（对指令行为生效）

---

## Filters 扩展（COMMAND 专用）

在 triggers.filters 中新增（可选）：

```jsonc
{
  "command_kind_any": ["ATTACK","CAST_SKILL"], // any-of
  "skill_id": 1001,                            // 复用现有 skill_id filter
  "item_id": 2001                              // 新增：仅 COMMAND 有意义
}
```

约定：
- `command_kind_any`：只对 COMMAND 生效；用于 any-of 匹配
- `item_id`：只对 COMMAND 生效；当 ctx.item_id=-1 时视为不匹配
- `skill_id`：已存在 filters.skill_id，可直接复用（ctx.skill_id 由 CommandContext 提供）

---

## Actions 扩展（COMMAND 专用）

新增一个最小 action：

1) `CANCEL_COMMAND`
```jsonc
{ "kind":"CANCEL_COMMAND" }
```

语义：
- 仅对 `event_type=COMMAND` 有意义
- 在 `CMD_BEFORE` 中触发：将 `ctx.cancel=true`

> 其它“附带效果”（例如使用道具后加盾/回血）仍复用现有 actions（ADD_SHIELD/HEAL/APPLY_BUFF…），作用对象通过 scope 解析到 runtime 的 stats/buffs。

---

## 运行时落点

### 1) EventIndex / BuffCore

- `BuffCore.emit_event("COMMAND","CMD_BEFORE", command_ctx)`
- `BuffCore.emit_event("COMMAND","CMD_AFTER", command_ctx)`

其中 runtime 仍通过 `ctx.meta["runtime"]` 注入（stats_by_entity / buff_by_entity），保持与 DAMAGE 一致。

### 2) 战斗系统对接（示例）

回合执行流程（伪代码）：

1) 组装 `CommandContext`
2) `buff_actor.emit_event(COMMAND, CMD_BEFORE, ctx)`
3) 如果 `ctx.cancel==true`：终止执行（记录日志/回放）
4) 执行真实指令逻辑（可能产生一次或多次 `DamagePipeline.deal_damage`）
5) `buff_actor.emit_event(COMMAND, CMD_AFTER, ctx)`

---

## 测试与 Demo（验收）

### Tests
新增 `tests/rpg/test_command_events_phase1.gd`：
- `CANCEL_COMMAND`：对 ESCAPE 生效，ctx.cancel=true；战斗系统模拟层断言“未执行逃跑逻辑”
- `BASIC_ATTACK tag`：ATTACK skill_id=xxx 且 tags_mask 包含 BASIC_ATTACK 时，listener 命中
- `USE_ITEM`：按 item_id 过滤命中（为后续道具系统铺路）

### Demo
在 `buff_ui_demo` 增加 3 个 scenario：
- command_cancel_escape
- command_basic_attack_tag
- command_use_item

HUD：
- Listeners 中能看到 COMMAND 的 listeners 与 action 摘要（含 CANCEL_COMMAND）

---

## 验收标准

- [ ] enums/event_index 支持 COMMAND + 新 phases（不破坏现有 DAMAGE）
- [ ] validators：放行 command filters 与 CANCEL_COMMAND
- [ ] tests 全绿 + demo 可复现
- [ ] 设计上可支持你未来的 “多种普攻技能，但都吃普攻加成”

