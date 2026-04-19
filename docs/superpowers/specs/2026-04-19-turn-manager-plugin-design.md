# TurnManager（回合制战斗）插件设计 Spec

日期：2026-04-19  
目标工程：Godot 4.x（GDScript）  
依赖插件：`omnibuff`、`turn_skill_system`  

> 本文档是 **设计规格说明（Spec）**：定义接口、数据契约、事件时序、模块边界、可测试性要求。  
> **实现计划（Plan）** 将在你确认本 spec 后再生成。

---

## 1. 背景与目标

你已有两个插件：
- **OmniBuff**：高性能 Buff/数值/伤害管线（含 `DamagePipeline`、`OmniTurnComponent`、replay 等）。
- **Turn Skill System**：JSON 驱动技能系统（`SkillRuntime.cast*`）、目标选择（`Grid/TargetingRegistry`）、效果（`EffectRegistry`）、事件总线（`BattleEventBus`）、以及被动/光环（`PassiveManager/AuraManager`）。

本插件 TurnManager 的职责是补齐“回合制 RPG 战斗系统”的第三块拼图：**战斗流程与回合编排的唯一权威**，并把关键节点映射到 Turn Skill System 的事件总线，从而驱动技能、被动、光环、伤害/治疗等效果系统闭环运行。

### 1.1 目标（Goals）
- 支持 **经典 JRPG**：**每轮按速度重排**行动顺序；同速时 **玩家阵营优先**；同阵营同速时 **稳定排序**。
- TurnManager **直接使用单位 Node** 作为 `Grid` 里的 unit（不额外包 Adapter）。
- 以“事件驱动”为核心：TurnManager 在关键节点向 `BattleEventBus` 派发事件，从而驱动 `turn_skill_system` 的被动/光环与技能效果链。
- 以 OmniBuff 的 `OmniTurnComponent` 作为 Buff/DOT 的 TurnStart/TurnEnd tick 编排工具，确保稳定顺序与复盘友好。
- 提供最小可用闭环：2v2（或任意单位数）→ 回合推进 → 玩家/AI 选技能 → 技能结算（伤害/治疗/buff）→ DOT tick → 死亡处理 → 胜负结束。

### 1.2 非目标（Non-goals）
以下不在 TurnManager 插件内实现（但要留扩展点）：
- UI 菜单、动画播放、相机镜头、特效、音效等“表现层”。
- 高级战棋规则（地形阻挡、路径寻路、ZOC 等）。
- 复杂联网同步（可复盘/确定性 RNG 只作为扩展点）。

---

## 2. 术语与约定

- **Round（轮）**：一轮包含所有存活单位各行动一次（或被跳过一次）。每一轮开始会重算行动队列。
- **Turn（回合）**：轮到某个单位行动的一次流程（TurnStart → 选择行动 → 结算 → TurnEnd）。
- **Action（行动）**：单位本回合执行的命令，目前最小闭环以“施放技能（CastSkill）”为主。
- **事件总线**：`turn_skill_system` 的 `BattleEventBus`（signal：`event_emitted(event_type, data)`；方法：`emit_event(type, data)`）。

---

## 3. 外部依赖与对接接口（从现有代码抽取）

### 3.1 turn_skill_system 的稳定入口
- Autoload：`/root/TurnSkillRuntime`（脚本 `res://addons/turn_skill_system/runtime/skill_autoload.gd`）
  - 字段：`db/event_bus/targeting/effects/omnibuff/passive_manager/aura_manager/grid`
  - 方法：`ensure_ready()`
- 静态 API：`SkillRuntime.cast*`（脚本 `res://addons/turn_skill_system/runtime/skill_runtime.gd`）
  - `cast(skill_id, caster, primary_cell?, extra)`
  - `cast_to_unit(skill_id, caster, primary_target, extra)`
  - `cast_to_cell(skill_id, caster, primary_cell, extra)`
  - `simulate_cast*`（仅预测，不落地）
- 事件名：`EventNames`（`turn_skill_system/runtime/event_names.gd`）
  - 关键字段：`TURN_STARTED/TURN_ENDED/ACTION_STARTED/ACTION_FINISHED/SKILL_CAST_STARTED/SKILL_CAST_FINISHED/BEFORE_DAMAGE/AFTER_DAMAGE/...`

### 3.2 omnibuff 的稳定入口
- Autoload：`/root/OmniBuff`（命名空间式脚本资源集合）
- Tick 编排：`OmniTurnComponent`（`omnibuff/runtime/components/turn_component.gd`）
  - `on_turn_start(entity_ids_sorted, buff_by_entity, stats_by_entity?, pipeline?, ds?, replay?)`
  - `on_turn_end(entity_ids_sorted, buff_by_entity, stats_by_entity, pipeline, ds, replay?)`

> 结论：TurnManager 不重复造轮子，只负责在正确时机调用以上接口，并保证输入数据的“字段契约”与“稳定顺序”。

---

## 4. 插件产物与目录结构（建议）

插件名建议：`turn_manager`（也可改为你更喜欢的命名）

```
addons/
  turn_manager/
    plugin.cfg
    plugin.gd              # EditorPlugin：安装/卸载（可选）Autoload 或仅做编辑器集成
    runtime/
      turn_manager.gd      # 核心：TurnManager Node
      battle_context.gd    # BattleContext（Resource 或 RefCounted）
      turn_command.gd      # TurnCommand 数据结构（最小：CastSkill）
      initiative.gd        # InitiativeStrategy（本 spec 固定：每轮重排；但留接口）
      victory.gd           # VictoryCondition（默认：一方全灭）
```

> 是否做 Autoload：本 spec 默认 **不强制 Autoload**（推荐 TurnManager 作为场景节点）。  
> EditorPlugin 仍可以提供“创建示例场景/模板节点”等能力。

---

## 5. 数据契约（最重要：单位 Node 需要满足的字段）

### 5.1 Unit Node 最小字段契约（必须）
TurnManager 将直接把单位 Node 传给 `turn_skill_system.Grid` 与 `SkillRuntime`。因此单位对象必须满足：

- `entity_id: int`  
- `camp: String`（推荐 `"ally"` / `"enemy"`；至少两阵营可区分）
- `cell: Vector2i`（用于 3x3 Grid 的定位；与 `turn_skill_system` 的 Grid 契约一致）
- `stats`：OmniBuff 的 StatsComponent 实例（示例：`OmniBuff.StatsComponent.new(entity_id, ds)`）
- `buffs`：OmniBuff 的 BuffCore 实例（示例：`OmniBuff.BuffCore.new(ds, enums_rt)`）

### 5.2 Unit Node 可选字段/方法（建议）
- `get_speed() -> float`（**推荐作为标准入口**）
  - TurnManager 每轮重排 **以 `unit.get_speed()` 的返回值作为 speed**。
  - 速度的“来源/叠加规则”（装备、buff、地形、先手、迟缓等）由 Unit 自己封装，TurnManager 不关心细节。
- `speed: int/float`（可选）
  - 仅作为你项目侧的存储字段；TurnManager 默认不直接读取该字段（除非你将来扩展 TurnManager 配置支持 fallback）。
- `is_dead() -> bool` 或 `is_dead: bool`
  - 若缺失，TurnManager 采用“由 stats/HP 判断”的策略（需要配置 HP stat id；见 7.2）。

---

## 6. BattleContext（战斗运行时上下文）

TurnManager 不直接依赖 Autoload，但要允许“优先使用 Autoload，缺失则注入”的风格（与 `SkillRuntime._get_runtime(extra)` 一致）。

### 6.1 必需字段
- `grid: Grid`（`turn_skill_system/runtime/grid.gd`）
  - `grid.set_units(units)` 的 units 即为单位 Node 数组
- `event_bus: BattleEventBus`
- `dataset (ds)`：OmniBuff 编译后的 dataset
- `enums_rt`：OmniBuff 枚举运行时
- `runtime_dict: Dictionary`
  - `stats_by_entity: { entity_id: StatsComponent }`
  - `buff_by_entity: { entity_id: BuffCore }`
- `turn_component: OmniTurnComponent`
- `omnibuff_adapter: OmniBuffAdapter`（turn_skill_system 的适配层，内部要求 unit.stats / unit.buffs）
- `passive_manager: PassiveManager`
- `aura_manager: AuraManager`

### 6.2 可选字段
- `pipeline`：OmniBuff.DamagePipeline（若你希望 DOT tick 也走 pipeline）
- `replay`：OmniBuff.Replay（用于复盘；可先不接）
- `sources`：技能/物品等来源（如你要复用 OmniBattleExecutor 的命令体系统）

---

## 7. TurnManager Public API（对业务与 UI/AI 暴露）

> TurnManager 为 Node（建议 `class_name TurnManager`），以便在场景中挂载。

### 7.1 信号（Signals）
- `battle_started(units: Array[Node])`
- `round_started(round_index: int, queue: Array[Node])`
- `turn_started(actor: Node, turn_index: int)`
- `action_requested(actor: Node, valid_skill_ids: Array[String])`
- `action_committed(actor: Node, command: TurnCommand)`
- `action_resolving(actor: Node, command: TurnCommand)`
- `turn_ended(actor: Node, turn_index: int)`
- `battle_ended(result: Dictionary)`

> 表现层（UI/动画）只需要订阅这些信号；TurnManager 内部 **不得** 直接操作 UI 节点。

### 7.2 配置项（Exported / Setters）
为降低“强绑定某个 RPG 数据集”的风险，TurnManager 需要提供可配置策略：
- `ally_camp_name: String = "ally"`
- `enemy_camp_name: String = "enemy"`
- `hp_stat_id: String = "HP"`（用于默认死亡判定；当 unit 未提供 `is_dead()` 时生效）
- `stable_order_mode: String`（枚举）
  - `"spawn_index"`：加入战斗的顺序（TurnManager 内维护）
  - `"cell"`：按 cell 稳定排序（row/col）

### 7.3 方法（Methods）
最小闭环：
- `setup(context: BattleContext, units: Array[Node]) -> void`
- `start_battle() -> void`
- `stop_battle() -> void`
- `submit_player_command(command: TurnCommand) -> void`
- `get_state() -> int`
- `get_current_actor() -> Node`

扩展（可选）：
- `set_ai_controller(fn_or_object)`：为敌方提供默认 AI 选择
- `force_end_turn()`：用于 UI 快进/跳过

---

## 8. TurnCommand（行动命令）

为与 `SkillRuntime.cast*` 对齐，最小命令集只做：

### 8.1 CastSkillCommand
字段：
- `kind = "cast_skill"`
- `skill_id: String`
- `primary_cell: Vector2i`（推荐统一用 cell；`cast_to_unit` 作为语法糖）
- `extra: Dictionary = {}`

说明：
- TurnManager 负责补齐 `extra`：至少包含 `grid/dataset/enums_rt/runtime_dict/turn_index`。
- 若未来需要 deterministic RNG：在 `extra` 增加 `rng_seed/roll_key/skill_id_int/tags_mask/...`。

---

## 9. 行动顺序（每轮重排）算法

在 `ROUND_START` 阶段生成 `turn_queue`：

### 9.1 排序键（从高到低）
1) `speed`（降序，来自 `unit.get_speed()`）  
2) `camp_priority`（玩家阵营优先）  
   - `camp == ally_camp_name` → 1  
   - 其它 → 0  
3) `stable_order`（升序）

稳定排序来源：
- 若 `stable_order_mode == "spawn_index"`：使用 `units` 传入顺序生成 index
- 若 `stable_order_mode == "cell"`：按 `(cell.x, cell.y)` 排

### 9.2 跳过规则
队列推进时，若 actor：
- 已死亡 → 直接跳过
- 被“无法行动”状态影响 → 触发 turn_started/turn_ended（仍要跑 tick），但不进入 `REQUEST_ACTION`
  - “无法行动”的判定策略不在本 spec 定死：默认只提供 hook（见 11.2）

---

## 10. 状态机与事件时序（与 turn_skill_system 对齐）

### 10.1 TurnManager 状态枚举
- `IDLE`
- `ROUND_START`
- `TURN_START`
- `REQUEST_ACTION`
- `RESOLVE_ACTION`
- `TURN_END`
- `CHECK_END`
- `BATTLE_END`

### 10.2 每回合事件派发（必须）
以 turn_index 为“全局回合计数”（每个单位行动一次 +1；或按轮 +1，二选一需要实现时定口径）。本 spec 推荐：
- `turn_index`：**单位回合序号**（每个 actor 的 TurnEnd 后 +1），与 `SkillRuntime` 的 `extra.turn_index` 对齐更自然。

#### 10.2.1 TurnStart
顺序：
1) TurnManager：`turn_started(actor, turn_index)`（自身信号）
2) EventBus：`EventNames.TURN_STARTED`，data 至少：
   - `turn_index`
   - `actor_id`
3) OmniTurnComponent.on_turn_start：
   - `entity_ids_sorted`：按 entity_id 升序
   - `buff_by_entity / stats_by_entity / pipeline / ds / replay`（按 context 是否提供）
4) AuraManager：`refresh_all()`（建议在 turn start 后做一次刷新）

#### 10.2.2 RequestAction
1) 若 actor 为玩家控制：
   - TurnManager 发 `action_requested(actor, valid_skill_ids)`
   - UI 最终调用 `submit_player_command(command)`
2) 若 actor 为 AI：
   - TurnManager 调用 AI 决策回调直接生成 `command`

#### 10.2.3 ResolveAction（技能）
1) TurnManager：`action_resolving(actor, command)`
2) EventBus：`EventNames.ACTION_STARTED`（建议包含 skill_id）
3) 调用 `SkillRuntime.cast_to_cell(command.skill_id, actor, command.primary_cell, extra)`
   - `extra` 必须包含：
     - `grid`
     - `dataset`
     - `enums_rt`
     - `runtime_dict`
     - `turn_index`
   - 允许包含：
     - `roll_key`（若你做 deterministic RNG）
     - `rng_seed`
4) EventBus：`EventNames.ACTION_FINISHED`（附带 result 摘要）

> 注意：`SkillRuntime` 内部会自行 emit `SKILL_CAST_STARTED/FINISHED`，以及 damage/heal 相关事件。

#### 10.2.4 TurnEnd
1) OmniTurnComponent.on_turn_end（稳定 tick + turn_index++ 在组件内部）
2) EventBus：`EventNames.TURN_ENDED`
3) TurnManager：`turn_ended(actor, turn_index)`
4) AuraManager：`refresh_all()`（建议在 turn end 后做一次刷新，以处理移动/死亡导致的差集）

---

## 11. 扩展点（未来不会推翻主框架）

### 11.1 胜负判定 VictoryCondition
默认：一方（ally 或 enemy）全部死亡 → battle_end。

扩展：
- 击杀 Boss
- 存活 N 轮
- 护送/守点等

接口建议：
- `check(units) -> {ended: bool, winner: String, reason: String}`

### 11.2 行动可用性（眩晕/沉默等）
TurnManager 不直接耦合具体 buff_id，但提供 hook：
- `can_actor_take_action(actor, context) -> bool`

默认实现：
- 仅检查“死亡”。
可选实现（你后续决定）：
- 通过 omnibuff 的 buff state / tags / runtime_dict 进行判定。

### 11.3 deterministic RNG（可复盘随机）
为与现有 `turn_skill_system`/`omnibuff` 的 `turn_index/roll_key/rng_seed` 参数体系对齐：
- TurnManager 维护 `rng_seed`（战斗开始生成或注入）
- 每个行动维护 `roll_key`（从 0 开始，命中段数/目标数递增）
- 将二者塞入 `SkillRuntime.extra`

---

## 12. 错误处理与失败策略

### 12.1 技能施放失败
`SkillRuntime.cast*` 返回 `{"ok": false, "errors": [...]}` 时：
- TurnManager 必须：
  - 发 `ACTION_FINISHED`（带失败原因）
  - 将本回合作为“已消耗行动”（默认不重选），或允许“重选一次”（可配置）

本 spec 默认：**失败也结束本回合**（减少流程分叉），后续可加配置项改成“允许重选”。

### 12.2 上下文缺失
若缺失 `dataset/enums_rt/runtime_dict`：
- TurnManager 在 `start_battle` 前 assert/报错，禁止进入战斗循环（因为 non-simulate cast 会失败）。

---

## 13. 测试策略（与 gut 集成）

工程内已包含 GUT 插件，因此 TurnManager 插件应提供最小单元测试：

### 13.1 排序测试
- 给 4 个单位 Node，设置不同 speed/camp/cell
- 断言每轮生成的队列顺序满足：
  - speed 降序
  - 同速玩家优先
  - 同速同阵营稳定排序

### 13.2 事件时序测试（冒烟）
- 准备最小 battle_context（参考 `turn_skill_system/demo/demo_battle.gd`）
- 执行 1 个回合：
  - 断言 EventBus 捕获到 `TURN_STARTED -> ACTION_STARTED -> SKILL_CAST_STARTED -> ... -> TURN_ENDED`

---

## 14. 最小里程碑（MVP）

MVP 必须完成：
1) `setup(context, units)`：能把 units 塞进 grid，并建立 runtime_dict
2) `start_battle()`：能推进至少 1 轮
3) 玩家单位：能通过 `submit_player_command(CastSkillCommand)` 施放一个技能并结算
4) 触发 `OmniTurnComponent` tick（turn_start/turn_end）
5) 死亡判定 + 胜负结束

---

## 15. 未决问题（实现前确认）
这些点不影响本 spec 主体，但实现时需要你拍板：
1) `turn_index` 口径：✅ **按“单位回合序号”**（每个单位完成一次 Turn 后 +1）。同时单独维护 `round_index`（每轮 +1）。
2) speed 来源：✅ **使用 `unit.get_speed()`**（TurnManager 每轮重排调用该方法）。
3) HP/死亡判定：✅ 提供可配置 `hp_stat_id`，默认：`hp_stat_id: String = "HP"`（优先使用 `unit.is_dead()`，缺失时使用 stats+hp_stat_id 判定）。
