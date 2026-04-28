# OmniBuff 迁移指南

> 从旧版 OmniBuff 升级到 v0.5.0 的注意事项

---

## 1. OmniModifierRef 新增字段

**影响范围**：直接创建 `OmniModifierRef` 的代码

**变更**：新增 `op_int: int` 和 `phase_int: int` 字段，默认值为 0。

**迁移**：
- 旧代码无需修改，新字段有默认值
- 建议在创建 ModifierRef 时同时设置 `op_int` 和 `phase_int`，以获得 `recompute()` 的整数比较优化

```gdscript
# 旧写法（仍然兼容）
var mr := OmniModifierRef.new()
mr.op = "ADD"
mr.phase = "FLAT"

# 新写法（推荐）
var mr := OmniModifierRef.new()
mr.op = "ADD"
mr.phase = "FLAT"
mr.op_int = 0    # ADD
mr.phase_int = 2 # FLAT
```

## 2. OmniCompiledDataset 新增字段

**影响范围**：直接访问 `ds.buff_defs` 的代码

**变更**：
- 新增 `buff_defs_compiled: Array`（预编译 BuffDef 数组）
- 新增 `derived_from_int: PackedInt32Array` 和 `derived_ratio: PackedFloat32Array`

**迁移**：
- `ds.buff_defs` 仍然可用，用于调试和显示
- 热路径代码建议使用 `ds.buff_defs_compiled[bdid]` 代替 `ds.buff_defs[bdid]`

## 3. OmniManifestLoader.Result 新增字段

**影响范围**：使用 `load_dataset_full()` 的代码

**变更**：新增 `mod_conflicts: Array` 字段

**迁移**：无需修改，新字段默认为空数组。如需检查 Mod 冲突：

```gdscript
var res = ManifestLoader.load_dataset_full(manifest_path, true)
for conflict in res.mod_conflicts:
    print("Mod conflict: %s %s replaced by %s" % [
        conflict.type, conflict.id, conflict.mod_path])
```

## 4. Mod 覆盖系统

**影响范围**：manifest.json 配置

**变更**：manifest.json 新增 `mods` 数组支持

**迁移**：在 manifest.json 中添加 `mods` 配置：

```json
{
  "mod_overrides": {
    "policy": "last_wins_by_id",
    "report_conflicts": true
  },
  "mods": [
    {"dir": "mods/my_mod"}
  ]
}
```

Mod JSON 文件格式：

```json
{
  "type": "buff_defs",
  "buffs": [
    {"id": "existing_buff_id", ...}
  ]
}
```

- `type` 必须与 manifest 中的文件类型匹配（如 `buff_defs`/`skill_defs`/`stat_defs`）
- 同 id 条目按 `last_wins_by_id` 策略替换
- 新 id 条目追加到列表末尾

## 5. Debug HUD 场景结构变更

**影响范围**：自定义 Debug HUD 场景的代码

**变更**：
- Stats Tab 从 `ScrollContainer > RichTextLabel` 改为 `VBoxContainer > GridContainer + ScrollContainer > RichTextLabel`
- Buffs Tab 新增 `BuffsToolbar` HBoxContainer
- 新增 Timeline Tab

**迁移**：如果自定义了 debug_hud.tscn，需要重新基于新版场景文件修改。

## 6. BuffCore.event_trace_fn

**影响范围**：使用 BuffCore 的代码

**变更**：新增 `event_trace_fn: Callable` 属性，默认为空 Callable

**迁移**：无需修改。如需追踪事件：

```gdscript
buffs.event_trace_fn = func(et: String, ph: String, ids: PackedInt32Array):
    print("Event: %s/%s hit=%s" % [et, ph, ids])
```

## 7. StatsCore recompute 整数比较

**影响范围**：自定义 StatsCore 子类或直接操作 modifiers 的代码

**变更**：`recompute()` 方法现在使用 `m.op_int` 和 `m.phase_int` 进行整数比较，而非 `m.op` 和 `m.phase` 的字符串比较

**枚举值映射**：
- op_type: ADD=0, MUL=1, OVERRIDE=2, CLAMP=3, FORMULA=4
- apply_phase: BASE=0, CONVERT=1, FLAT=2, PERCENT=3, FINAL=4, CLAMP=5

**迁移**：确保所有自定义创建的 `OmniModifierRef` 都设置了 `op_int` 和 `phase_int`。未设置时默认为 0（ADD/BASE），可能导致行为不正确。
