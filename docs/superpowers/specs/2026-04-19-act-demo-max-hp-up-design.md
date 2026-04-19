# 技能/BUFF：MAX_HP +30%（3回合，可刷新）设计 Spec

日期：2026-04-19  
适用工程：Godot 4.7  
依赖：
- OmniBuff：`res://addons/omnibuff`
- TurnSkillSystem：`res://addons/turn_skill_system`
- TurnManager：`res://addons/turn_manager`
- 数据集：`res://data/rpg_tests/manifest.json`

目标：以**纯数据驱动**方式实现一个“给自己加 MAX_HP +30%”的主动技能，并通过 TurnManager 的资源同步（保持百分比 + floor）在**同回合内**让 `HP` 按比例同步到新的 `MAX_HP`。

---

## 1. 需求与规则口径（已确认）

1) BUFF 效果：`MAX_HP +30%`  
- 语义：`op="MUL", phase="PERCENT", value=0.30` 表示 **×1.30**

2) BUFF 持续时间：3 回合  
- 用 OmniBuff duration：`{ "type": "TURNS", "turns": 3, "tick_phase": "TURN_END" }`

3) 重复施放：刷新到 3 回合  
- 用 stack refresh：`refresh_policy="RESET_TO_MAX"`

4) 技能施放目标：**自己**  
- TurnSkillSystem `apply_buff` 参数：`scope="caster"`

---

## 2. 设计概览

### 2.1 新增一个 OmniBuff BUFF（rpg_tests）
在 `res://data/rpg_tests/buff_defs.json` 新增条目：
- `id`: `buff_demo_max_hp_pct_30_3t`
- `duration`: `TURNS(3)`，`tick_phase: TURN_END`
- `stack`: `REPLACE`, `max_stack=1`, `refresh_policy=RESET_TO_MAX`, `ownership_mode=GLOBAL`
- `effects`: 单条 modifier
  - stat=`MAX_HP`
  - op=`MUL`
  - phase=`PERCENT`
  - priority=`110`（沿用现有 `buff_atk_pct_5` 的优先级习惯）
  - value=`0.30`

### 2.2 新增一个 TurnSkillSystem 主动技能（data/skills）
在 `res://addons/turn_skill_system/data/skills/active/` 新增文件：
- `act_demo_max_hp_up.json`
  - `id`: `act_demo_max_hp_up`
  - `type`: `active`
  - `targeting`: 选择策略采用 `single_cell` + `camp: "ally"`（方便 demo 中对自己 cell 施放）
  - `on_cast`: `apply_buff`，params：
    - `buff_id`: `buff_demo_max_hp_pct_30_3t`
    - `scope`: `"caster"`

并将其注册进：
- `res://addons/turn_skill_system/data/skills/index.json`

### 2.3 Demo 调整（验证闭环）
在 `res://addons/turn_manager/demo/demo_battle.gd`：
- 让 entity 1 在 turn 1 不再用脚本直接改 MAX_HP
- 改为施放 `act_demo_max_hp_up`（对自己 cell）
- 仍保留日志：在 `action_finished` / `turn_end` 打印 `HP/MAX_HP`，验证保持百分比（floor）

---

## 3. 验收标准（Acceptance）

### 3.1 行为验收（手动跑 demo）
运行 `res://addons/turn_manager/demo/demo_battle.tscn`，观察日志：
1) entity 1 turn 1 施放 `act_demo_max_hp_up` 后（同回合）：
   - `MAX_HP` 提升（约 1.3 倍；具体取决于原 MAX_HP）
   - TurnManager 在 `ACTION_FINISHED` 后同步资源：`HP/MAX_HP` 百分比保持不变，且使用 floor
2) 战斗仍可正常推进并最终触发 `battle_ended`

### 3.2 数据验收（JSON 正确性）
- `buff_defs.json` 能被 `rpg_tests/manifest.json` 正常加载与编译
- skill json 能被 `turn_skill_system` 的 SkillDB 加载
- `SkillRuntime.cast_to_cell("act_demo_max_hp_up", ...)` 返回 ok=true

---

## 4. 回归测试建议（GUT）

至少新增一个冒烟测试：
- 用 rpg_tests dataset 创建一个 unit（含 stats/buffs）
- 调用 `SkillRuntime.cast_to_cell("act_demo_max_hp_up", caster, caster.cell, extra)`
- 断言：`MAX_HP` 的 final 增加，且（若在 TurnManager 同步后）`HP` 按比例变化

> 注：TurnManager 的“保持百分比同步”已由 `test_resource_sync_keep_ratio.gd` 覆盖；这里主要验证“技能→apply_buff→BuffCore 修改 MAX_HP”链路能跑通。

