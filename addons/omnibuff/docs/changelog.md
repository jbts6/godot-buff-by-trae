# OmniBuff Changelog

## [0.5.0] - 2026-04-28

### 新增

- **Scenario 数据驱动化 (P2-3)**：新增 `ScenarioRunner` 类，支持从 JSON 文件加载和执行测试场景，包含 `apply_buff`/`deal_damage`/`turn_end`/`turn_start`/`add_base` 步骤和 `eq`/`ne`/`gt`/`lt`/`ge`/`le` 断言
- **Debug HUD 交互式增强 (P2-1)**：
  - Stats Tab 新增 SpinBox 编辑器，可直接修改 base 值并实时触发脏标记重算
  - Buffs Tab 新增 Apply Buff / Remove 按钮，支持通过 buff_id 施加和通过 inst_id 移除
  - 新增 Timeline Tab，记录每次 `emit_event` 调用的事件类型、阶段、命中实例和关联 buff
  - BuffCore 新增 `event_trace_fn: Callable` 钩子，HUD 可注入回调以追踪事件
- **策划配置指南 (P2-4)**：新增 `docs/designer_guide.md`，包含配方索引、常见错误排查表、枚举值中文速查表、伤害管线阶段流程、Scenario JSON 测试格式
- **BuffDef 子结构预编译 (P3-1)**：
  - 新增 `compiled_buff_def.gd`，定义 `BuffDefCompiled`/`EffectCompiled`/`TriggerCompiled`/`FilterCompiled`/`ActionCompiled`/`ConditionCompiled`/`DotCompiled` 预编译类型
  - `DatasetCompiler` 编译时将 raw Dictionary 转换为预编译类型，枚举值预转为 int，tag 预转为 bitmask
  - `OmniCompiledDataset` 新增 `buff_defs_compiled: Array` 字段
  - `_rebuild_instance_modifiers()` 和 `_conditions_satisfied_compiled()` 已迁移至使用预编译数据
- **StatsCore 派生属性计算优化 (P3-2)**：
  - 派生属性定义预编译为 `derived_from_int: PackedInt32Array` 和 `derived_ratio: PackedFloat32Array`，消除运行时 `stat_id()` 字符串查找
  - `recompute()` 方法从字符串比较 (`op == "ADD" and phase == "FLAT"`) 迁移为整数比较 (`op_i == 0 and ph_i == 2`)
  - `OmniModifierRef` 新增 `op_int` 和 `phase_int` 字段
- **Mod 覆盖系统 (P3-3)**：
  - `OmniManifestLoader` 新增 `_apply_mod_overrides()` 方法，支持从 `manifest.json` 的 `mods[]` 目录加载 Mod JSON 文件
  - 按 `last_wins_by_id` 策略合并 buff/skill/stat 等数据，同 id 条目被 Mod 替换
  - 冲突记录写入 `Result.mod_conflicts[]`，包含 type/id/base_index/mod_path/action
- **性能基准/压力测试 (P3-4)**：新增 `test_stress_benchmark.gd`，包含 100 次 apply/remove 循环、10 实体×5 Buff、100 次伤害管线调用、Scenario 压力测试、编译数据查找速度基准

### 变更

- `OmniModifierRef` 新增 `op_int: int` 和 `phase_int: int` 字段（默认 0，向后兼容）
- `OmniCompiledDataset` 新增 `buff_defs_compiled`/`derived_from_int`/`derived_ratio` 字段
- `OmniManifestLoader.Result` 新增 `mod_conflicts: Array` 字段
- `debug_hud.tscn` 场景结构重构：Stats Tab 改为 VBoxContainer（含 StatsEditArea GridContainer + StatsScroll），Buffs Tab 新增 BuffsToolbar，新增 Timeline Tab
- `debug_hud.gd` 全面重写，新增 `set_stat_base()`/`apply_buff_by_id()`/`remove_buff_by_inst_id()`/`_install_event_trace_hooks()`/`_on_event_trace()`/`_refresh_timeline()` 等方法

### 修复

- 修复 `test_scenario_runner.gd` 中 `OmniScenarioRunner` 标识符未声明和 `:=` 类型推断失败问题
- 修复 `scenario_runner.gd` 中 `_ds.stat_id()` 返回 Variant 导致 `:=` 类型推断失败的问题

---

## [0.4.0] - 2026-04-28 (Phase A/B/C)

### 新增

- **condition_type 对齐 (P0-1)**：enums.json 新增 `STAT_THRESHOLD`/`EQUIP_SET_COUNT_GE`/`HAS_TAG`/`STAT_GE`，validators 校验 condition_type 合法性
- **ownership_key 唯一性 (P0-2)**：`_ownership_key` 从 `(bdid << 16) ^ (k & 0xffff)` 改为 `(bdid * 1000003) ^ k`，消除碰撞
- **DatasetCompiler 补全 (P0-3)**：编译 skill_defs/equipment(CSV→Dict)/set_bonus/damage_pipeline，BattleExecutor 从 ds 读取 skill 数据
- **deal_damage_v2 API (P1-1)**：新增 `make_request()` + `deal_damage_v2()` 版本化 API
- **SHA-256 指纹缓存 (P1-2)**：DatasetCompiler 计算 SHA-256 fingerprint 用于缓存失效
- **JSON Schema 验证 (P1-3)**：新增 7 个 JSON Schema 文件，ajv-cli 验证数据契约
- **load_order 排序 (P1-4)**：ManifestLoader 按 `load_order` 排序文件加载顺序
- **枚举反向查找 (P3-9)**：EnumsRuntime 新增 `reverse_name()` 方法，O(1) 查找
- **RFC 4180 CSV 解析 (P3-5)**：csv_reader 重写，支持引号字段、转义引号、空字段、尾逗号
- **Bootstrap 合并 (P3-6)**：OmniBuffSingleton._ready() 吸收 bootstrap 功能，删除 omnibuff_bootstrap.gd

### 测试

- 新增 22 个测试文件，覆盖所有 P0-P3 变更
- 全量回归 166 测试通过
