# turn_skill_system 调用与集成指南

面向“战斗系统/AI/工具链”的调用文档，重点描述：如何准备上下文、如何调用 `SkillRuntime`、如何解析返回结构与事件、以及 JSON 技能数据的关键约束。

> 约定：示例代码尽量避免使用 `:=`（Godot 4 静态分析在 Variant/动态对象上可能推断失败）。

---

## 1. 你需要准备什么（最小运行上下文）

### 1.1 Unit 契约（必需字段）

任意能被技能系统使用的单位对象（Node / RefCounted / Object）必须具备以下字段：

| 字段 | 类型 | 含义 |
|---|---|---|
| `entity_id` | `int` | 全局唯一实体 ID |
| `camp` | `String` | `"ally"` 或 `"enemy"`（当前 targeting 默认按此判敌我） |
| `cell` | `Vector2i` | 3×3 格子坐标，范围 `0..2` |
| `stats` | OmniBuff StatsComponent | OmniBuff 数值组件（用于伤害/治疗） |
| `buffs` | OmniBuff BuffCore | OmniBuff buff 容器（用于 apply/remove） |

### 1.2 Grid（必需）

`Grid` 保存场上单位列表并提供基础查询（FIRST/ALL/cross 等 targeting 依赖）：

```gdscript
var grid = Grid.new()
grid.set_units([unit_a, unit_b, unit_c])
```

### 1.3 OmniBuff 上下文（cast 必需，simulate 可选）

`SkillRuntime.cast(...)`（simulation=false）要求 `extra` 内提供：

| key | 类型 | 说明 |
|---|---|---|
| `dataset` | `OmniBuff.CompiledDataset` | 由 manifest 编译得到 |
| `enums_rt` | `OmniBuff.EnumsRuntime` | enums 运行时映射（enum_int/tag_mask） |
| `runtime_dict` | `Dictionary` | `{"stats_by_entity": {...}, "buff_by_entity": {...}}` |

`SkillRuntime.simulate_cast(...)`（simulation=true）允许不提供上述三项（只返回预测结构）。

**runtime_dict 结构：**
```gdscript
var runtime_dict = {
  "stats_by_entity": {
    1001: unit_a.stats,
    2001: unit_b.stats,
  },
  "buff_by_entity": {
    1001: unit_a.buffs,
    2001: unit_b.buffs,
  }
}
```

---

## 2. 调用入口（固定 API）

### 2.1 cast / cast_to_unit / cast_to_cell

```gdscript
var r = SkillRuntime.cast("act_demo_single", caster, null, {
  "grid": grid,
  "dataset": ds,
  "enums_rt": enums_rt,
  "runtime_dict": runtime_dict,
  "turn_index": 1,
  "roll_key": 0,
  "rng_seed": 0,

  # 公式变量（可选）：推荐 AI/工具侧传入纯数据，避免直接暴露对象
  "a_stats": {"ATK": 100},
  "t_stats": {"DEF": 20}
})
```

```gdscript
var r1 = SkillRuntime.cast_to_unit(skill_id, caster, target_unit, extra)
var r2 = SkillRuntime.cast_to_cell(skill_id, caster, Vector2i(1, 1), extra)
```

### 2.2 simulate_cast（AI 评估/预览）

```gdscript
var sim = SkillRuntime.simulate_cast(skill_id, caster, primary_cell, {
  "grid": grid,
  "a_stats": {"ATK": 100}
})
```

`simulate_cast` 目标：
- **不落地**（不真实修改 HP、不真实 apply/remove buff）
- 返回 `predicted_deltas` 便于 AI/提示/预估

---

## 3. 返回结构（推荐按结构化方式消费）

`cast()` / `simulate_cast()` 的返回是一个 `Dictionary`，建议业务侧按下列字段读取：

| 字段 | 类型 | 说明 |
|---|---|---|
| `ok` | bool | 成功/失败 |
| `simulation` | bool | 是否模拟 |
| `skill_id` | String | 技能 ID |
| `caster_id` | int | 施法者实体 ID |
| `targets` | Array | 目标摘要（unit_id + cell） |
| `effects` | Array | 执行结果（按 effect kind） |
| `events` | Array | 捕获到的战斗事件（用于回放/表现/AI 特征） |
| `resolved_formulas` | Array | 公式追溯（expr/vars/result） |
| `errors` | Array[String] | 失败错误码（稳定字符串） |
| `issues` | Array | JSON 校验器 issues（file_path/field_path/message） |
| `predicted_deltas` | Array | 仅 simulation=true 时，预测变化 |

**effects 元素示例：**
```json
{"kind":"damage","value":123,"meta":{"used":"deal_damage","turn_index":1}}
{"kind":"apply_buff","value":0,"meta":{"buff_id":"buff_atk_flat_20","inst_id":12}}
{"kind":"heal","value":45,"meta":{"amount":45}}
```

---

## 4. 事件（EventBus）与对外事件名

事件名常量见：`res://addons/turn_skill_system/runtime/event_names.gd`

目前已定义（节选）：
- `turn_started` / `turn_ended`
- `skill_cast_started` / `skill_cast_finished`
- `before_damage` / `after_damage`
- `before_heal` / `after_heal`
- `unit_died` / `unit_moved` / `grid_changed`

业务系统可以通过 Autoload（`TurnSkillRuntime.event_bus`）订阅事件：

```gdscript
var rt = get_node("/root/TurnSkillRuntime")
rt.ensure_ready()
rt.event_bus.event_emitted.connect(func(t, data):
  print("[evt]", t, data)
)
```

---

## 5. 技能 JSON 关键约束（权威数据源）

### 5.1 目录结构

```
addons/turn_skill_system/data/skills/
  index.json
  active/*.json
  passive/*.json
  aura/*.json
```

`index.json` 用于加速：运行时先加载索引，`SkillDB.get_skill(id)` 再 lazy-load 单文件。

### 5.2 Active（必备字段）

```json
{
  "version": 1,
  "id": "act_xxx",
  "type": "active",
  "name": "技能名",
  "targeting": "FIRST",
  "on_cast": [],
  "on_hit": []
}
```

补充字段（可选，但常用）：
- `hit_count`：多段
- `hit_base_damage`：多段伤害基值/表达式（兼容 rpg_tests）
- `damage_type` / `element` / `tags`

### 5.3 Passive（triggers）

```json
{
  "version": 1,
  "id": "pas_xxx",
  "type": "passive",
  "triggers": [
    {"event":"turn_started","chance":1.0,"effects":[{"kind":"apply_buff","params":{"buff_id":"..."}}]}
  ]
}
```

### 5.4 Aura（range + enter/exit）

```json
{
  "version": 1,
  "id": "aur_xxx",
  "type": "aura",
  "aura": {
    "range": {"rule":"ally_front_row","params":{}},
    "on_enter": [{"kind":"apply_buff","params":{"buff_id":"..."}}],
    "on_exit":  [{"kind":"remove_buff","params":{"buff_id":"..."}}]
  }
}
```

---

## 6. Targeting（目标选择）

当前支持：
- 字符串模式：`"FIRST"` / `"ALL"`
- 对象模式：`{"rule":"single_cell"}` / `{"rule":"cross"}` 等

返回目标结构（TargetingRegistry 产物）：
```gdscript
{
  "unit": <unit_obj>,
  "unit_id": 2001,
  "cell": Vector2i(0, 1),
  "role": "primary" # or secondary
}
```

---

## 7. Effect（效果）

当前内置 kind：
- `damage`：走 `OmniBuffAdapter.deal_damage(...)`
- `apply_buff` / `remove_buff`：走 `BuffCore.apply_buff/remove_by_buff_id`
- `heal`：目前为最小实现（M1 会把 heal 正式落地并纳入 omnibuff 口径）

`damage` 支持参数：
- `amount`（数字）
- `amount_expr`（字符串表达式，使用 `Formula` 求值）
- `rounding`（默认 floor；可为 ceil/round）

---

## 8. 最推荐的战斗系统集成方式（Autoload）

当插件启用后，Autoload `TurnSkillRuntime` 会被安装。

业务侧在战斗开始时做一次初始化：
1. `rt.ensure_ready()`
2. `rt.grid = grid`（或在 cast extra 里传 grid）
3. `rt.omnibuff.setup(ds, enums_rt, runtime_dict)`
4. 注册被动/光环（可选）：`rt.passive_manager.register_unit_passives(...)`、`rt.aura_manager.register_aura(...)`

示例：
```gdscript
var rt = get_node("/root/TurnSkillRuntime")
rt.ensure_ready()
rt.grid = grid
rt.omnibuff.setup(ds, enums_rt, runtime_dict)
rt.passive_manager.register_unit_passives(caster, ["pas_demo_turn_start_buff"])
rt.aura_manager.register_aura(caster, "aur_demo_front_row_atk")
rt.aura_manager.refresh_all()
```

---

## 9. 常见问题（FAQ）

### Q1: 为什么不要用 `:=`？
Godot 4 在解析期会尝试对 `:=` 的右值做静态推断；当右值来自动态对象/Variant（如 `Dictionary.get()`、`RefCounted` 字段、某些返回 Variant 的 API）时会推断失败并在**解析期报错**。因此在本插件内，推荐使用：
- `var x = ...`（不强制推断）
- 或显式类型：`var skills: Array = ...` / `var sr: Dictionary = ...`

### Q2: 事件怎么用于表现层？
表现层推荐只消费 `events[]`（回放友好），而不是直接读 `effects[]`；`effects[]` 更偏“结算摘要”，`events[]` 更偏“过程与时序”。

