# 战斗语义化播报（BattleNarrator + 面板）设计 Spec

日期：2026-04-19  
范围：回合制 demo（TurnManager + TurnSkillSystem + OmniBuff）  
目标：提供一套“人能看懂”的战斗过程播报系统，默认简洁，可切换为详细；输出到**游戏内面板**（RichTextLabel），并可选同时打到控制台（addons/log）。

---

## 1. 需求（已确认）

1) 语义化播报，例：
   - “战斗开始！”
   - “主角被动技能：xx 生效，xxx（效果）”
   - “计算出手顺序：主角 > xx > xx …”
   - “回合 1：主角使用 xx，目标 xx，造成 xx 伤害，目标 HP 300/400”
   - AOE：逐目标列出受到伤害与当前 HP
2) 默认 **简洁模式**，可切换为 **详细模式**（同一套数据源/事件流）。
3) 输出位置：**游戏内面板**（RichTextLabel）。时间戳默认关闭。

---

## 2. 方案概览（推荐：事件驱动播报）

### 2.1 数据输入
以 `BattleEventBus.event_emitted(event_name, data)` 为主输入，利用现有事件：
- `battle_started`
- `turn_started` / `turn_ended`
- `action_started` / `action_finished`
- `skill_cast_started` / `skill_cast_finished`
- `before_damage` / `after_damage`
- `before_heal` / `after_heal`
- `unit_died`

并补齐两个“语义事件”（让被动/光环/队列能说人话）：
- `buff_applied` / `buff_removed`：由 Apply/Remove Buff effect 触发
- `turn_order_computed`：由 TurnManager 在每次重排队列后触发

### 2.2 输出
新增 `BattleLogPanel`（Window/Control + RichTextLabel），订阅 `BattleNarrator` 输出的“播报行”：
- `line_emitted(bbcode_line: String, meta: Dictionary)`
- `block_started(title_line: String)`（可选：用于回合分段）

`BattleNarrator` 内部使用 `addons/log` 的 `Log.to_printable(...)` 来生成 **BBCode 彩色文本**（而不是直接 print），从而：
- UI 面板里也能享受 log.gd 的 pretty/color 规则
- 控制台可选同样输出（调试开关）

---

## 3. 核心组件设计

### 3.1 BattleNarrator（runtime，可复用）
路径建议：`res://addons/turn_manager/runtime/battle_narrator.gd`

职责：
1) 监听 event_bus，维护“当前回合/当前施法”上下文  
2) 将事件翻译为中文播报行（BBCode）  
3) 输出到 UI（通过 signal），可选镜像到控制台（Log.pr/prn）

接口：
- `bind(event_bus, grid, dataset, skill_db, runtime_dict, name_map:Dictionary = {}, opts:Dictionary = {})`
- `set_detail_level(level: int)`  
  - 0=简洁、1=详细
- signals：
  - `line_emitted(bbcode_line: String, meta: Dictionary)`
  - `clear_requested()`（可选）

内部状态（最小）：
- `current_turn_index: int`
- `current_actor_id: int`
- `current_skill_id: String`
- `pending_targets: Array[int]`（从 damage/heal 事件收集）
- `last_hp_by_eid: Dictionary` / `last_mp_by_eid: Dictionary`（用于输出“变化前→变化后”）

命名映射：
- `name_map[eid] = "主角/队友/Boss/随从"`（demo 里注入）
- `skill_db` 取 `skill.name`（若缺省则输出 skill_id）

### 3.2 BattleLogPanel（UI）
路径建议：
- `res://addons/turn_manager/runtime/ui/battle_log_panel.tscn`
- `res://addons/turn_manager/runtime/ui/battle_log_panel.gd`

UI 需求（最小）：
- RichTextLabel（bbcode_enabled=true，自动滚动）
- 按钮：清空、复制（可选）
- Toggle：`简洁/详细`（切换 narrator.detail_level）

---

## 4. 事件 → 播报语义映射（核心）

### 4.1 开战前流程
- `battle_started`：
  - 输出：“战斗开始！”
  - 可在此后输出一次 `turn_order_computed`（如果 TurnManager 立即 emit）
- `buff_applied`（由被动/光环/技能引发）：
  - 输出：“【{caster}】获得效果：{buff_id 或 buff_name}”
  - 若能从 ds 反查 buff.name，优先用 name
- `turn_order_computed`：
  - 输出：“计算出手顺序：主角(15) > Boss(12) > …”
  - speed 来自 unit.get_speed() 或 stats.get_final(SPEED)

### 4.2 回合内流程（简洁模式）
- `turn_started`：
  - 输出：“回合 {turn}：{actor} 行动”
- `action_started`：
  - 输出：“{actor} 使用【{skill}】（目标：单体/全体）”
- `after_damage` / `after_heal`：
  - **简洁模式**：同一技能内按 target 聚合后输出 1 行或 N 行（AOE N 行）
  - 逐条输出：“{target} 受到 {dmg} 伤害，HP {cur}/{max}”
  - 治疗：“{target} 恢复 {heal}，HP {cur}/{max}”
- `unit_died`：
  - 输出：“{target} 倒下了！”

### 4.3 详细模式（可切换）
在简洁基础上追加：
- before_damage 的 base_damage
- 伤害结算 meta（若 omnibuff.deal_damage 返回 meta 含减伤/暴击等信息，可选择性展示）
- 每次 action_finished 后输出全员 HP/MP 概览（可选开关）

---

## 5. 验收标准

1) demo 运行时出现“战斗开始/回合开始/技能施放/伤害或治疗/死亡/出手顺序”等人话播报  
2) 默认简洁；点击切换后变为详细（同一场战斗即时生效）  
3) AOE 技能会对每个目标输出独立的“受到伤害 + 当前 HP/MaxHP”行  
4) 被动/光环导致的 buff 施加会播报（依赖 buff_applied 事件）  

