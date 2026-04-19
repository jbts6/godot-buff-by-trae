# 2v2 小型战斗 Demo：主角/队友 vs Boss/随从（技能与属性）设计 Spec

日期：2026-04-19  
适用插件：
- OmniBuff：`res://addons/omnibuff`
- TurnSkillSystem：`res://addons/turn_skill_system`
- TurnManager：`res://addons/turn_manager`

目标：设计一套可用于 Demo 测试的 **2v2 小型战斗配置**（属性 + 技能），满足用户给定约束，并能在现有 turn_skill_system + omnibuff + turn_manager 的链路中跑通。

---

## 1. 需求清单（原始约束）

1) 主角：≥2 主动攻击技能（其中 1 个 AOE），≥1 提高速度的被动技能  
2) 队友：≥1 主动治疗技能，≥1 “减少受到伤害”的光环技能  
3) 基础速度：Boss 最高；但由于主角被动，进入战斗后主角速度最高先手  
4) 属性强度：Boss > 主角 > 随从 > 队友  
5) Boss：≥2 主动攻击技能（其中 1 个 AOE）  
6) 所有 AOE：冷却 ≥2 回合；伤害系数越高，冷却越长  
7) 属性至少配置：HP、MP、ATK、DEF、SPEED  

---

## 2. 系统口径与实现假设（避免“设计无法落地”）

### 2.1 SPEED 的落地口径
- 在 `rpg_tests/stat_defs.json` 新增 `SPEED`（数值来源统一走 `unit.stats.get_final(SPEED)`）
- `unit.get_speed()` 返回 `stats.get_final(SPEED)`，从而 buff/被动可以通过 modifier 影响出手顺序

### 2.2 冷却（Cooldown）的落地口径
turn_skill_system 当前 skill schema 不内建冷却字段与运行时约束，因此本 demo 采用：
- 在 skill JSON 中新增字段：`cooldown_turns: int`（**扩展字段**，SkillValidator 不会拒绝未知字段）
- 由 TurnManager（或 demo AI 层）维护每个单位的 `cooldown_remaining[skill_id]` 并在回合开始递减  
- 尝试施放冷却未结束技能时：AI 不会选择（或 TurnManager 拒绝并返回失败）

补充规则（已确认）：
- **Boss 的所有主动技能都有冷却**，不能连续回合释放。
- 当角色所有技能都在冷却时，改为 **普攻**（普攻本身不进入冷却）。

### 2.3 “开战先手被动”的事件口径（已确认采用）
新增事件：`EventNames.BATTLE_STARTED`（字符串 `"battle_started"`）。
- TurnManager 在 `start_battle()` 首轮排队前 emit `battle_started`
- PassiveManager 支持监听该事件触发被动（与 `turn_started` 同一触发机制）

---

## 3. 单位阵容与属性（2v2）

> 注意：这里的 HP/MP 指 “当前值”，MAX_HP/MAX_MP 由你的资源系统决定；此配置只强调用户要求的字段与强度关系。

### 3.1 站位
本设计中，“光环技能”按你的游戏口径定义为：**作用于所有友军的被动技能**。因此站位不再影响光环覆盖范围（不限定前排/后排）。  
Demo 仍沿用 3x3 grid，给出一套固定站位便于观察与日志定位：
- Ally：主角 (0,1)、队友 (0,2)
- Enemy：Boss (2,1)、随从 (2,0)

### 3.2 属性表（满足强度与速度约束）
单位属性（示例数值，可在平衡阶段微调；但必须保持相对关系）：

| 阵营 | 单位 | HP | MP | ATK | DEF | SPEED（基础） | 说明 |
|---|---|---:|---:|---:|---:|---:|---|
| ally | 主角 HERO | 220 | 80 | 55 | 22 | 10 | 主力输出；靠被动开战加速先手 |
| ally | 队友 ALLY | 160 | 120 | 25 | 18 | 7 | 偏辅助；治疗 + 减伤光环 |
| enemy | Boss BOSS | 420 | 100 | 80 | 35 | **12** | 基础速度最高；属性整体最强 |
| enemy | 随从 MINION | 240 | 40 | 40 | 20 | 9 | 中等威胁 |

满足：
- 基础速度：Boss(12) > 主角(10) > 随从(9) > 队友(7)
- 进入战斗后：主角被动提供 SPEED 加成，使主角 > Boss
- 属性强度：Boss > 主角 > 随从 > 队友（HP/ATK/DEF 体现）

---

## 4. 技能设计（skill_id + 行为）

命名约定（建议）：
- 主动：`act_...`
- 被动：`pas_...`
- 光环：`aur_...`

### 4.1 主角（HERO）

#### 主动 1：单体连击（无冷却）
- `id`: `act_hero_strike`
- `type`: `active`
- `targeting`: `"FIRST"`（或 `single_cell` enemy）
- 伤害：单体，系数中等
- `cooldown_turns`: 0

建议伤害（用公式表达系数）：
- `amount_expr = "20 + a.ATK * 1.1"`，rounding=floor

#### 主动 2：旋风斩（AOE，CD=2）
- `id`: `act_hero_whirlwind`
- `type`: `active`
- `targeting`: `"ALL"`（all_enemies）
- AOE 技能冷却 ≥2：满足
- `cooldown_turns`: 2

建议伤害（AOE 系数较低）：
- `amount_expr = "10 + a.ATK * 0.7"`

#### 被动：开战先手（提高速度）
- `id`: `pas_hero_battle_haste`
- `type`: `passive`
- trigger：`event: "battle_started"`
- effect：`apply_buff`，scope=caster

对应 buff（见 5.1）：`buff_hero_speed_flat_5_3t`（SPEED +5，3回合，可刷新或不刷新均可；本 demo 建议可刷新）

> 预期效果：主角基础 10 + 5 = 15 > Boss 12，开战先手。

---

### 4.2 队友（ALLY）

#### 主动：治疗（无冷却）
- `id`: `act_ally_heal`
- `type`: `active`
- `targeting`: `single_cell` + `camp:"ally"`
- `cooldown_turns`: 0

建议治疗：
- 直接复用 `heal` effect：`amount: 35`（或未来引入 MATK 后用公式）

#### 光环：守护光环（减少受到伤害）
- `id`: `aur_ally_guard`
- `type`: `aura`（实现层仍走 AuraManager；在游戏设计语义上等价于“作用于全体友军的被动光环”）
- range：新增规则 `ally_all`（覆盖 owner 同阵营全体存活单位）
- on_enter：`apply_buff`（scope=target）
- on_exit：`remove_buff`（scope=target, remove_scope=ALL）

对应减伤 buff：`buff_dmg_reduce_20p`（你已有，DMG_REDUCE +0.20）

---

### 4.3 Boss（BOSS）

#### 主动 1：粉碎重击（单体高伤，无冷却或 CD=1）
- `id`: `act_boss_crush`
- `targeting`: `"FIRST"`
- `cooldown_turns`: 2（Boss 所有主动技能均在冷却，避免连续释放）
- `amount_expr = "30 + a.ATK * 1.4"`（高系数）

#### 主动 2：毁灭震荡（AOE，CD=4）
AOE 冷却 ≥2 且系数更高 → CD 更长。
- `id`: `act_boss_quake`
- `targeting`: `"ALL"`
- `cooldown_turns`: 4
- `amount_expr = "20 + a.ATK * 1.0"`

#### 普攻：撕裂（无冷却，用于“全部技能都在冷却”时）
- `id`: `act_boss_basic`
- `targeting`: `"FIRST"`
- `cooldown_turns`: 0
- `amount_expr = "10 + a.ATK * 0.9"`

---

### 4.4 随从（MINION）

#### 主动：穿刺（单体，低伤，无冷却）
- `id`: `act_minion_stab`
- `targeting`: `"FIRST"`
- `cooldown_turns`: 0
- `amount_expr = "10 + a.ATK * 0.9"`

---

## 5. BUFF 设计（omnibuff/buff_defs）

### 5.1 主角开战加速 buff
- `id`: `buff_hero_speed_flat_5_3t`
- duration：`TURNS=3, tick_phase=TURN_END`
- stack：`REPLACE`, `refresh_policy=RESET_TO_MAX`
- effect：`modifier stat=SPEED op=ADD phase=FLAT priority=100 value=5`

### 5.2 队友光环减伤 buff
复用现有：
- `buff_dmg_reduce_20p`（DMG_REDUCE +0.20）

---

## 6. Demo 行为（AI 选择策略）

为保证 demo 可重复观察并覆盖 cooldown：

### 6.1 Hero AI（简化）
1) 若 `act_hero_whirlwind` 冷却为 0：优先释放（AOE）
2) 否则释放 `act_hero_strike`

### 6.2 Ally AI（简化）
1) 若任一 ally（含自己）HP% < 60%：释放 `act_ally_heal`（目标选 HP% 最低 ally）
2) 否则普攻：`act_ally_basic`（无冷却的低伤单体）

### 6.3 Boss AI（简化）
1) 若 `act_boss_quake` 冷却为 0：优先 AOE
2) 否则若 `act_boss_crush` 冷却为 0：使用单体重击
3) 否则普攻：`act_boss_basic`

### 6.4 Minion AI（固定）
始终 `act_minion_stab`

---

## 7. 验收标准

1) 开战后首个行动者是主角（由 `battle_started` 被动 + SPEED buff 驱动）  
2) AOE 技能遵守 cooldown（Hero AOE CD=2；Boss AOE CD=3）  
3) 伤害与治疗可正常结算；光环能对前排 ally 生效（DMG_REDUCE 生效可通过伤害对比观察）  
4) 战斗最终能结束（胜负成立）  
