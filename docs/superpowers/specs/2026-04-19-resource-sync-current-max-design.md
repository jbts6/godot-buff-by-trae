# 资源型属性（当前/最大）同步设计 Spec（HP/MP/RAGE）

日期：2026-04-19  
适用范围：`res://addons/omnibuff` + `res://addons/turn_skill_system` + `res://addons/turn_manager`  

## 1. 背景与目标

很多 RPG 的资源型属性（HP/MP/怒气）都具有：
- **当前值**（CUR）
- **最大值**（MAX）

当 MAX 因装备/BUFF/技能变化时，需要把 CUR 同步到新的 MAX 上，同时保持“血条/蓝条/怒气条的百分比”不突变。

本设计的目标：
1) 引入资源对：`HP/MAX_HP`、`MP/MAX_MP`、`RAGE/MAX_RAGE`  
2) 当 MAX 变化时，按“**保持百分比** + **floor**”规则同步 CUR  
3) 同步范围：**仅当前行动者**（TurnManager 的 current actor）  
4) 必须支持关键场景：**当前行动者在自己回合内释放技能，提高 MAX_*（例如 MAX_HP）**，同步后 CUR 百分比保持不变  
5) 不推翻现有系统：不重做 omnibuff 的 stats/buff 核心；通过轻量模块 + 明确接入点实现

---

## 2. 数据集命名约定（已确认）

### 2.1 命名方案
保持：
- `HP` 表示 **当前血量**（CUR）

新增：
- `MAX_HP`
- `MP`
- `MAX_MP`
- `RAGE`
- `MAX_RAGE`

### 2.2 迁移约定（关键）
当前 `res://data/rpg_tests/stat_defs.json` 中 `HP` 存在 derived（例如 from STR）的设计。  
为了避免 “STR 变化 → 当前 HP 被动变化” 的反直觉效果，要求：
- 将 HP 的 derived 迁移到 `MAX_HP`
- `HP` 自身不再 derived（HP 只表示当前值，由战斗流程与效果系统改动）

---

## 3. 同步规则（保持百分比 + floor）

对任意资源对 `(CUR, MAX)`：

### 3.1 输入
- old_cur：同步前 CUR 当前值
- old_max：同步前 MAX 值（来自快照 snapshot）
- new_max：同步时刻 MAX 的当前值（从 stats 读取）

### 3.2 计算
- 若 `old_max <= 0`：`ratio = 0`
- 否则：`ratio = clamp(old_cur / old_max, 0..1)`
- `new_cur = floor(ratio * new_max)`
- `new_cur = clamp(new_cur, 0..new_max)`

### 3.3 写回
将 `CUR` 写回到 `new_cur`（写回层必须统一，见 6.2）。

---

## 4. 快照机制（推荐方案，已确认采用）

为保证“本回合内 MAX 变化”的正确性，需要保存 “上一次同步时的 MAX”：

### 4.1 数据结构（TurnManager 内）
- `resource_snapshot_by_entity: Dictionary`
  - key：`entity_id:int`
  - value：`Dictionary`（max_stat_id_int -> last_max_value: float）

示例：
```text
resource_snapshot_by_entity[1001][MAX_HP_id] = 120.0
resource_snapshot_by_entity[1001][MAX_MP_id] = 40.0
```

### 4.2 快照初始化
在首次需要同步某个实体时：
- 将 snapshot 初始化为当前 MAX（避免 old_max=0 的异常路径）
- 并将 CUR clamp 到 [0..MAX]（可选）

---

## 5. 同步时机（仅当前行动者，但覆盖回合内 MAX 变化）

对当前行动者 `actor`，每回合执行两次同步：

### 5.1 TurnStart 同步（进入 REQUEST_ACTION 前）
在 TurnManager 的 `TURN_START` 阶段中：
1) 处理 `OmniTurnComponent.on_turn_start(...)`（BUFF/DOT tick）
2) 刷新 aura（若有）
3) **调用 `sync_resources_keep_ratio(actor)`**
4) 进入 `REQUEST_ACTION`

目的：处理“上回合遗留/持续 BUFF/光环”等导致的 MAX 变化，使玩家开始操作时资源状态稳定。

### 5.2 ActionFinished 同步（行动结算后，TURN_END 前）
在 TurnManager 完成 `SkillRuntime.cast_to_cell(...)` 并派发 `ACTION_FINISHED` 后：
1) **调用 `sync_resources_keep_ratio(actor)`**
2) 再进入 `TURN_END`

目的：覆盖关键场景：本回合内施放技能/挂 buff 提高 MAX_*，同步后 CUR 百分比保持不变。

> 第一版采用“无条件同步一次”，不需要检测 MAX 是否真的发生变化（简单可靠，成本极低）。

---

## 6. 读写策略与层级约束

### 6.1 读取（CUR/MAX）
- 统一通过 `unit.stats.get_final(stat_id)` 读取 CUR 与 MAX

### 6.2 写回（CUR）
必须定义一个统一写回策略，避免到处 `add_base` 引发漂移。

第一版策略（最小可用）：
- 允许对 CUR 使用 “设置当前值” 的方式写回（推荐提供一个 helper，避免散落代码）
- 若 omnibuff 当前没有 `set_base(stat_id, value)`，则采用：
  - `delta = new_cur - old_cur`
  - `stats.add_base(cur_id, delta)`

要求：
- 写回 CUR 必须 clamp 到 [0..MAX]
- 写回仅针对当前行动者（actor）

---

## 7. 单元测试要求（GUT）

至少新增以下回归：

### 7.1 同步公式测试（floor + 百分比）
给定：
- old_max=100, old_cur=50（50%）
- new_max=121
期望：
- new_cur = floor(0.5*121)=60

边界：
- old_max<=0 → ratio=0
- old_cur>old_max → ratio clamp 到 1

### 7.2 “回合内 MAX 变化”测试（关键）
模拟流程：
1) actor TurnStart：快照记录 old_max
2) 行动中施加效果：MAX_HP 增加（通过 stats.add_base 或 buff）
3) ActionFinished 同步：HP 应按 old_ratio 同步到 new_max

---

## 8. Demo 验收用例

在 `turn_manager/demo/demo_battle.tscn` 或新增 demo：
- 设置 actor 初始：HP=50, MAX_HP=100
- 在其回合施放一个技能（或直接在 demo 中模拟）将 MAX_HP 提升到 200
- 同步后 HP 应变为 `floor(0.5 * 200)=100`

MP/RAGE 同理可添加一个简化案例。

