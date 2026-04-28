# OmniBuff Phase D 执行计划（P2/P3）

> 创建日期：2026-04-28
> 状态：已批准
> 版本：1.0

---

## 1. 执行顺序与依赖关系

```
P3-9 (HUD枚举反查) ← 无依赖，最先执行
    ↓
P3-5 (CSV解析器增强) ← 无依赖
    ↓
P3-6 (Bootstrap合并) ← 无依赖
    ↓
P2-2 (跨平台确定性RNG) ← 无依赖
    ↓
P2-1 (HUD交互式增强) ← 依赖 P3-9
    ↓
P2-3 (Scenario数据驱动化) ← 依赖 P3-5
    ↓
P2-4 (策划配置指南) ← 依赖 P2-3（引用 Scenario JSON 示例）
    ↓
P3-1 (BuffDef紧凑数组) ← 依赖 P0-3（编译产物格式稳定）
    ↓
P3-2 (派生属性优化) ← 无依赖
    ↓
P3-3 (Mod覆盖系统) ← 依赖 P1-4（load_order已实现）
    ↓
P3-4 (性能基准) ← 依赖 P2-3（ScenarioRunner可复用）
    ↓
P3-7 (Changelog) ← 所有代码变更完成后执行
    ↓
P3-8 (API文档对齐) ← 所有代码变更完成后执行
```

---

## 2. P3-9：HUD 枚举反查优化

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D1 | EnumsRuntime 新增 `_reverse_tables` 字段，在 `from_enums_json()` 中构建 | `runtime/core/enums_runtime.gd` |
| D2 | 新增 `reverse_name(enum_name, code)` 方法 | 同上 |
| D3 | debug_hud.gd 中 `_enum_name_from_int()` 改用 `enums_rt.reverse_name()` | `demo/debug_hud.gd` |
| D4 | 新增测试 | `tests/rpg/test_enums_reverse_lookup.gd` |

### 风险评估

- 风险：极低。仅新增字段和方法，不修改现有逻辑。
- 应对：无特殊应对措施。

---

## 3. P3-5：OmniCsv 解析器增强

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D5 | 重写 `load_rows()` 支持 RFC 4180 双引号字段和转义 | `config/parsers/csv_reader.gd` |
| D6 | 将 `split(",", false)` 改为 `split(",", true)` 保留空列 | 同上 |
| D7 | 新增测试：含逗号/换行/引号的字段、空行、BOM | `tests/rpg/test_csv_parser.gd` |

### 风险评估

- 风险：重写解析器可能破坏现有 equipment.csv 的解析结果。
- 应对：新解析器必须对现有 CSV 文件产生完全相同的输出；新增回归测试。

---

## 4. P3-6：Bootstrap 与 Singleton 职责合并

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D8 | omnibuff_singleton.gd 的 _ready() 中新增所有脚本的 preload | `runtime/omnibuff_singleton.gd` |
| D9 | omnibuff.gd（EditorPlugin）移除 bootstrap Autoload 注册 | `omnibuff.gd` |
| D10 | 删除 omnibuff_bootstrap.gd | 删除文件 |
| D11 | 更新 project.godot 移除 bootstrap Autoload | `project.godot` |
| D12 | 全量 GUT 回归验证 | 手动 |

### 风险评估

- 风险：合并后 Godot 脚本解析时序问题可能仍存在。
- 应对：Singleton 的 _ready() 在 Autoload 生命周期中执行，与 Bootstrap 的 _ready() 时机相同；若仍有问题，可回退。

---

## 5. P2-2：跨平台确定性 RNG 保障

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D13 | 修改 `_roll01()` 为定点数映射：`u / 429497` 得到 [0,10000) 整数，再除以 10000.0 | `runtime/core/damage_pipeline.gd` |
| D14 | 新增 `use_fixed_point` 配置变量 | 同上 |
| D15 | 新增测试：定点模式与浮点模式结果偏差 < 0.001 | `tests/rpg/test_rng_cross_platform.gd` |
| D16 | 全量 GUT 回归验证（确保现有测试不受影响） | 手动 |

### 风险评估

- 风险：定点映射 `u / 429497` 可能改变现有命中/暴击判定的结果。
- 应对：先运行现有 hit/crit 测试验证结果是否一致；若不一致，调整除数使映射范围仍为 [0,1)。

---

## 6. P2-1：Debug HUD 交互式增强

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D17 | Stats Tab 中为 base 值添加 SpinBox 编辑器 | `demo/debug_hud.gd` + `demo/debug_hud.tscn` |
| D18 | Buffs Tab 中添加 Apply Buff / Remove 按钮 | 同上 |
| D19 | 新增 Timeline Tab：记录 emit_event 调用 | 同上 |
| D20 | BuffCore.emit_event() 中追加时间线记录钩子 | `runtime/core/buff_core.gd` |
| D21 | 新增测试 | `tests/rpg/test_hud_interactive.gd` |

### 风险评估

- 风险：HUD 场景文件修改可能破坏现有 UI 布局。
- 应对：仅新增节点，不修改现有节点属性；新增 Tab 页而非修改现有 Tab。

---

## 7. P2-3：Scenario 数据驱动化

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D22 | 创建 ScenarioRunner 类 | `demo/scenario_runner.gd` |
| D23 | 定义 Scenario JSON schema | `addons/omnibuff/schemas/scenario.schema.json` |
| D24 | 创建示例 Scenario JSON 文件 | `data/rpg_tests/scenarios/` |
| D25 | buff_ui_demo.gd 中新增 JSON scenario 加载逻辑 | `demo/buff_ui_demo.gd` |
| D26 | 新增测试 | `tests/rpg/test_scenario_runner.gd` |

### 风险评估

- 风险：JSON scenario 无法表达所有 Callable scenario 的复杂逻辑。
- 应对：保留 Callable 模式作为后备；JSON scenario 覆盖 80% 常见场景。

---

## 8. P2-4：策划配置指南

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D27 | 编写配方索引（10+ 常见效果配方） | `addons/omnibuff/docs/designer_guide.md` |
| D28 | 编写常见错误排查表 | 同上 |
| D29 | 编写枚举值中文速查表 | 同上 |

---

## 9. P3-1：BuffDef 子结构预编译为紧凑数组

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D30 | CompiledDataset 新增紧凑数组字段 | `runtime/core/compiled_data.gd` |
| D31 | DatasetCompiler 新增 effects/triggers 紧凑编译 | `config/compiler/dataset_compiler.gd` |
| D32 | BuffCore 适配：从紧凑数组读取 effects/triggers | `runtime/core/buff_core.gd` |
| D33 | 新增测试 | `tests/rpg/test_buff_compact_layout.gd` |

### 风险评估

- 风险：BuffCore 修改量大（2144 行中约 40% 涉及 effects/triggers 访问）。
- 应对：分步实施——先新增紧凑字段（不删旧路径），验证通过后再逐步替换访问方式。

---

## 10. P3-2：StatsCore 派生属性计算优化

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D34 | StatsCore 新增 `_dirty_sources` 字段 | `runtime/core/stats_core.gd` |
| D35 | 修改 `mark_dirty()` 追加脏源记录 | 同上 |
| D36 | 修改 `get_final()` 仅重算脏源依赖子集 | 同上 |
| D37 | 新增测试 | `tests/rpg/test_stats_dirty_source_optimization.gd` |

---

## 11. P3-3：Mod 覆盖系统实现

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D38 | ManifestLoader 新增 `load_dataset_with_mods()` | `config/manifest_loader.gd` |
| D39 | 实现 mod 合并逻辑（last_wins_by_id + 冲突日志） | 同上 |
| D40 | 新增测试 | `tests/rpg/test_mod_override.gd` |

---

## 12. P3-4：性能基准/压力测试 Scenario

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D41 | 创建 benchmark_scenario.gd | `demo/benchmark_scenario.gd` |
| D42 | 在 UI Demo 中添加 Benchmark Tab | `demo/buff_ui_demo.gd` |
| D43 | 新增测试 | `tests/rpg/test_benchmark_scenario.gd` |

---

## 13. P3-7：Changelog 与迁移指南

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D44 | 创建 CHANGELOG.md | `addons/omnibuff/CHANGELOG.md` |
| D45 | 创建 v1_to_v2 迁移指南 | `addons/omnibuff/docs/migration/v1_to_v2.md` |

---

## 14. P3-8：API 文档与代码对齐

### 任务分解

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| D46 | 更新 api.md：新增 deal_damage_v2 签名 | `addons/omnibuff/docs/api.md` |
| D47 | 统一文档示例使用 v2 入口 | `docs/*.md` |
| D48 | 标注保留字段实现状态 | `addons/omnibuff/docs/api.md` |

---

## 15. 验收检查点

| 检查点 | 验收内容 |
|--------|----------|
| CP-D1 | P3-9 + P3-5 + P3-6 完成后：枚举反查 O(1)、CSV RFC 4180 兼容、Bootstrap 已合并，全量 GUT 通过 |
| CP-D2 | P2-2 完成后：RNG 定点模式可选，现有 hit/crit 测试不受影响 |
| CP-D3 | P2-1 完成后：HUD 可编辑 Stat/Apply Buff/Remove Buff/Timeline Tab 可用 |
| CP-D4 | P2-3 + P2-4 完成后：ScenarioRunner 可执行 JSON scenario，策划配置指南交付 |
| CP-D5 | P3-1 + P3-2 完成后：BuffDef 紧凑数组编译通过，派生属性脏源优化生效 |
| CP-D6 | P3-3 + P3-4 完成后：Mod 覆盖系统可用，性能基准可运行 |
| CP-D7 | P3-7 + P3-8 完成后：Changelog 交付，API 文档与代码一致 |
