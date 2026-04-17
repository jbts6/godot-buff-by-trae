# OmniBuff Phase 1 收尾：Stack 精细控制 + DEATH/REVIVE 事件域（设计）

## 背景（对齐 roadmap 缺口）

依据 `omnibuff-buff-system-roadmap.md`，Phase 1 当前主干已覆盖：
- Filters 扩展（skill_id、crit、shield absorbed 等）
- Action 扩展（heal、shield、dispel、lifesteal、reflect…）
- COMMAND 事件域（回合制指令）

仍剩的高收益缺口（Phase 1 收尾优先）：
1) **Stack 精细控制**：目前只有 `APPLY_BUFF.add_stacks`，缺少“减层/设层/只改层不刷新”等能力
2) **更多事件域**：优先做 `DEATH/REVIVE`（并补充用例：击杀回血、复活清 DEBUFF）

---

## 目标

### A. Stack 精细控制（Phase 1 收尾）

在 `trigger.action.kind` 增加两类能力：

1) `SET_STACKS`：将某个目标 buff 的层数直接设为指定值（常用于复活清 debuff、清除某种层数等）
2) `ADD_STACKS`：对某个目标 buff 增/减层（允许负数，代表减层；常用于技能命中叠层/消耗层数）

并保证：
- 可选择目标 buff：按 `buff_id` 精确命中
- 作用对象仍使用现有 `scope`（SELF/SOURCE/TARGET）
- 对 stack 改动后，Stats/Buff 的联动保持正确（需要复用现有 apply/remove 流程或新增“只改 stacks”的最小增量 API）

### B. 新增 `DEATH/REVIVE` 事件域

增加一个“生命周期事件域”，供战斗系统显式触发：
- `event_type = LIFE`
- `event_phase = DEATH | REVIVE`

并提供最小 ctx：
- `LifeContext`（RefCounted）
  - `actor_id`：发生事件的单位（死亡者/复活者）
  - `source_id`：可选，导致该事件的来源（killer；没有则 -1）
  - `tags_mask`：用于过滤（例如 BOSS / HERO 等；可选）

> 说明：Phase 1 不做 KILL/ASSIST 事件域；但通过 `LifeContext.source_id` 先覆盖“击杀者是谁”的核心诉求。

---

## 数据协议（JSON）

### 1) Stack actions

#### ADD_STACKS
```jsonc
{
  "kind": "ADD_STACKS",
  "buff_id": "buff_bleed",
  "delta": -1,
  "min_stack": 0,          // 可选：下限 clamp（默认 0）
  "max_stack": 99          // 可选：上限 clamp（默认取该 buff 的 stack.max_stack）
}
```

#### SET_STACKS
```jsonc
{
  "kind": "SET_STACKS",
  "buff_id": "buff_bleed",
  "value": 0
}
```

语义约束：
- `buff_id` 必填
- `ADD_STACKS.delta` 必填（允许负数）
- `SET_STACKS.value` 必填（>=0）
- 当目标 buff 不存在：视为 no-op（不报错）

### 2) LIFE 事件域

Trigger 示例：
```jsonc
{
  "event_type": "LIFE",
  "event_phase": "DEATH",
  "scope": "SOURCE",
  "filters": { "require_hit": false },
  "action": { "kind": "HEAL", "value": 50.0 }
}
```

> 说明：LIFE 事件不走 hit/crit/伤害字段，filters 仅允许 tag_mask_any + stat_threshold + (可选) actor_id/source_id 精确过滤（本轮只做最小集合）。

---

## 运行时落点（实现边界）

### A. Stack 精细控制：BuffCore 增量 API

在 `OmniBuffCore` 增加两个最小 API（供 action 调用）：
- `add_stacks_by_buff_id(stats, buff_id_str, delta, ownership="ALL") -> int`：返回受影响实例数
- `set_stacks_by_buff_id(stats, buff_id_str, value, ownership="ALL") -> int`

实现策略（尽量低侵入）：
- 先定位匹配的 inst（复用 `remove_by_buff_id` 的匹配逻辑：按 buff_def_id 比对）
- 修改 `inst.stacks` 并按 clamp 处理
- 若 stacks 变为 0：等价于移除该实例（复用 remove 路径，确保 modifiers/listeners 清理一致）
- 若 stacks 变化需要影响 DOT 缩放：DotInstance 里 stacks 应同步更新（保持 DOT “按层数缩放”正确）

### B. LIFE 事件域：LifeContext + emit_event

- 新增 `life_context.gd`（类似 command_context）
- `BattleExecutor` 或更上层战斗系统，在单位死亡/复活时显式调用：
  - `buff_of_actor.emit_event("LIFE","DEATH", ctx)`
  - `buff_of_actor.emit_event("LIFE","REVIVE", ctx)`
- runtime 注入方式与 COMMAND 保持一致：`ctx.set_meta("runtime", runtime2)`

---

## Filters（LIFE 事件最小集合）

Phase 1 收尾只补“够用”的过滤：
- `tag_mask_any`（已存在）
- `stat_threshold`（已存在，依赖 runtime）
- （新增）`actor_id` / `source_id` 精确过滤（可选；方便“只对击杀者触发”）

---

## 测试与 Demo（验收）

### 1) Tests

新增 `tests/rpg/test_phase1_wrapup_stacks_and_life_events.gd` 覆盖：
1) **ADD_STACKS / SET_STACKS**
   - 给 defender 挂一个可叠层 debuff（3 层）
   - 执行 action：ADD_STACKS(delta=-1) → 变 2 层
   - SET_STACKS(value=0) → 该 buff 实例移除
2) **击杀回血（DEATH）**
   - 设 defender HP 为小值，造成一次致死伤害（或直接模拟死亡事件）
   - 触发 LIFE/DEATH：source_id=attacker_id
   - attacker 的 HP +50（或按配置）
3) **复活清 DEBUFF（REVIVE + DISPEL 或 SET_STACKS=0）**
   - 给 actor 挂 DEBUFF
   - LIFE/REVIVE 事件触发后，DEBUFF 被清理（推荐用 DISPEL_BY_TAG 或 SET_STACKS）

### 2) Demo（buff_ui_demo）

新增 2~3 个 scenario：
- stacks_add_remove
- life_death_kill_heal
- life_revive_clean_debuff

---

## 非目标

- 不做“阵营/单位类型/距离”等 selector 扩展（留到后续 Phase 1.5/2）
- 不做 KILL/ASSIST 完整事件域（仅用 source_id 覆盖击杀者的最小需求）

