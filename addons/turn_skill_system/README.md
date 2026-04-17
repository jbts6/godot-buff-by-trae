# turn_skill_system

JSON 权威的技能系统（active/passive/aura），集成 `addons/omnibuff`，并提供 Editor Dock 编辑器与最小 Demo。

## 1) 启用插件

1. 打开 Godot：`Project → Project Settings → Plugins`
2. 勾选：`Turn Skill System`
3. 启用后会自动安装 Autoload：`TurnSkillRuntime`

> 说明：启用/禁用插件会自动安装/卸载该 Autoload（不残留工程配置）。

## 2) 技能 JSON 与目录结构（权威数据源）

```
addons/turn_skill_system/data/skills/
  active/*.json
  passive/*.json
  aura/*.json
  index.json
```

### Active（参考 data/rpg_tests/skill_defs.json）
- `targeting`: 支持字符串 `"FIRST"`/`"ALL"`（兼容）或对象 `{rule, params, needs_primary, primary_role}`
- 效果容器：**以 `on_cast` / `on_hit` 为权威**
- 多段：`hit_count` + `hit_base_damage`（可选）

### Passive
- `triggers[]`：`event` + `chance` + `effects[]`

### Aura
- `aura.range` + `aura.on_enter` + `aura.on_exit`

## 3) index.json（索引 + 懒加载）

运行时只先读 `index.json`，`SkillDB.get_skill(id)` 时才读取对应 JSON 并缓存。

编辑器 Dock 内提供：
- `rebuild_index`：扫描三目录并更新 index.json

## 4) 对外调用：一行 cast + 便捷封装 + simulate

### 4.1 一行调用（固定 API）

```gdscript
var r := SkillRuntime.cast("act_demo_single", caster_unit, null, {
  "grid": grid,
  "dataset": ds,
  "enums_rt": enums_rt,
  "runtime_dict": runtime_dict,
  "turn_index": 1
})
```

### 4.2 便捷封装

```gdscript
SkillRuntime.cast_to_unit(skill_id, caster, target_unit, extra)
SkillRuntime.cast_to_cell(skill_id, caster, Vector2i(1, 1), extra)
```

### 4.3 simulate_cast（AI 评估）

```gdscript
var sim := SkillRuntime.simulate_cast(skill_id, caster, primary_cell, extra)
print(sim.predicted_deltas)
```

- `simulate_cast` 不会真实修改 HP / 不会真实 apply/remove buff
- 仅返回预测结构（predicted_deltas）

## 5) Editor Dock（编辑器面板）

启用插件后，右侧 Dock 会出现 `SkillEditorDock`：
- 搜索/筛选技能（name/id/tags）
- 打开并编辑 JSON（整份文本，天然保留 unknown fields）
- validate：校验关键字段与类型（定位到 file_path + field_path）
- save：稳定缩进写回（2 spaces）+ 尽量稳定字段顺序
- rebuild_index：重建 index.json
- simulate：构造最小战斗上下文并调用 `simulate_cast` 输出结果

## 6) Demo

打开场景：
`res://addons/turn_skill_system/demo/demo_battle.tscn`

运行后会在 Output 打印：
- passive：`turn_started` 触发给自己上 buff
- active：单体伤害（FIRST）
- active：十字范围伤害（cross）
- aura：前排光环 enter/exit 上下 buff（示例在 demo 中调用 refresh）

## 7) 扩展点

### 7.1 新增 Targeting 规则
在 `addons/turn_skill_system/runtime/targeting/` 新建 `xxx_targeting.gd`，实现：
```gdscript
func resolve(skill: Dictionary, caster, primary_cell, grid, extra: Dictionary) -> Array[Dictionary]
```
并在 `TargetingRegistry.register_defaults()` 注册 `rule_id`。

### 7.2 新增 Effect kind
在 `addons/turn_skill_system/runtime/effects/` 新建 `xxx_effect.gd`，实现：
```gdscript
func apply(effect: Dictionary, ctx: Dictionary, simulation: bool) -> Dictionary
```
并在 `EffectRegistry.register_defaults()` 注册。

## 8) omnibuff 对接点

所有对接集中在：
`addons/turn_skill_system/runtime/omni_buff_adapter.gd`

已实现：
- `apply_buff/remove_buff` → `OmniBuff.BuffCore.apply_buff/remove_by_buff_id`
- `damage` → `OmniBuff.DamagePipeline.deal_damage`（兜底 `deal_damage_v1`）

