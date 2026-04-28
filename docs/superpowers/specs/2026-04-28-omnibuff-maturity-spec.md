# OmniBuff 成熟化项目规范（Maturity Spec）

> 创建日期：2026-04-28
> 状态：已批准
> 版本：1.0

---

## 1. 项目目标

将 OmniBuff 从"最小可用版（MVP）"推进到"生产可用版"，核心目标：

1. **消除架构债务**：补全 DatasetCompiler 编译链路，消除运行时回溯原始 sources 字典的违规行为
2. **修复潜在 Bug**：修复 ownership_key 哈希冲突、condition_type 枚举不一致等已知问题
3. **提升接入体验**：交付 Tutorial 教程、JSON Schema、策划配置指南，降低新用户/策划接入门槛
4. **强化 API 兼容性**：引入版本化 API 策略，确保后续迭代不破坏现有调用方
5. **完善基础设施**：实现 Fingerprint 缓存校验、load_order 排序、CSV 解析器增强等声明但未实现的功能

## 2. 范围界定

### 2.1 IN SCOPE（本迭代范围内）

| 编号 | 工作项 | 优先级 | 类别 |
|------|--------|--------|------|
| P0-1 | condition_type 枚举与实现对齐 | P0 | 功能/Bug |
| P0-2 | ownership_key 哈希冲突修复 | P0 | 性能/Bug |
| P0-3 | DatasetCompiler 编译补全 | P0 | 功能/架构 |
| P0-4 | Tutorial 教程交付（8 章） | P0 | 文档 |
| P1-1 | API 版本化与兼容层规范化 | P1 | 兼容性 |
| P1-2 | Fingerprint 缓存校验实现 | P1 | 功能 |
| P1-3 | JSON Schema 正式定义 | P1 | 文档/质量 |
| P1-4 | load_order 排序逻辑实现 | P1 | 功能 |
| P2-1 | Debug HUD 交互式增强 | P2 | 体验 |
| P2-2 | 跨平台确定性 RNG 保障 | P2 | 兼容性 |
| P2-3 | Scenario 数据驱动化 | P2 | 体验 |
| P2-4 | 策划配置指南 | P2 | 文档 |
| P3-1 | BuffDef 子结构预编译为紧凑数组 | P3 | 性能 |
| P3-2 | StatsCore 派生属性计算优化 | P3 | 性能 |
| P3-3 | Mod 覆盖系统实现 | P3 | 功能 |
| P3-4 | 性能基准/压力测试 Scenario | P3 | 体验 |
| P3-5 | OmniCsv 解析器增强 | P3 | 兼容性 |
| P3-6 | Bootstrap 与 Singleton 职责合并 | P3 | 兼容性 |
| P3-7 | Changelog 与迁移指南 | P3 | 文档 |
| P3-8 | API 文档与代码对齐 | P3 | 文档 |
| P3-9 | HUD 枚举反查优化 | P3 | 性能 |

### 2.2 OUT OF SCOPE（本迭代范围外）

- EditorPlugin Inspector 自定义插件（需 Godot EditorPlugin API 深度适配，单独立项）
- EditorPlugin Dock 面板（同上）
- 完整回放执行器（Replay 只记录不驱动的架构变更较大）
- 联网游戏战斗校验（需服务端架构配合）
- Turn Manager / 行动顺序/速度系统（属于战斗框架层，非 Buff 核心层）

## 3. 技术栈要求

| 层面 | 要求 | 说明 |
|------|------|------|
| Godot 版本 | 4.7+ | 基线版本，headless/CI 需一致 |
| 脚本语言 | GDScript 2.0 | 遵循项目现有约定 |
| 测试框架 | GUT（仓库内 vendor） | `res://addons/gut/` |
| 数据格式 | JSON / CSV | 遵循现有 manifest 声明 |
| 编码规范 | 无 class_name 依赖 | 使用 `OmniBuff.Xxx` / preload 引用 |
| 类型标注 | 显式类型标注 | 避免裸 `:=` 推断（RefCounted 场景） |
| 注释规范 | 不添加注释 | 遵循项目 code style 约定 |
| 性能约束 | PERF(J2) | 禁止遍历全实体 keys / 全部 Buff |

## 4. 质量标准

### 4.1 代码质量

- 所有新增/修改代码必须通过现有 GUT 测试（0 fail）
- P0/P1 工作项必须新增对应测试用例
- 编译产物（CompiledDataset）的字段访问必须通过 int 索引，不得回溯原始 Dictionary
- 新增公开 API 必须在 `omnibuff_singleton.gd` 中注册

### 4.2 数据质量

- enums.json 的枚举值必须与代码实际使用一致
- 所有数据集（base_demo / rpg_tests）在 strict=true 模式下加载必须 0 error
- 新增 JSON Schema 必须能校验现有数据集通过

### 4.3 文档质量

- Tutorial 每章的代码示例必须可运行（从 demo/test 中提取）
- API 文档与代码签名必须一致
- 所有"保留字段"标注当前实现状态

### 4.4 兼容性标准

- `deal_damage_v1()` 签名不得变更
- `schema_version=1` 的数据集必须仍可正常加载
- 新增字段必须有默认值，不得破坏旧数据集

## 5. 交付物清单

### 5.1 代码交付物

| 交付物 | 路径 | 关联工作项 |
|--------|------|-----------|
| 修正后的 enums.json | `data/base_demo/enums.json` | P0-1 |
| 修正后的 buff_defs（condition_type 对齐） | `data/*/buff_defs.json` | P0-1 |
| 修正后的 ownership_key 哈希 | `runtime/core/buff_core.gd` | P0-2 |
| 补全的 DatasetCompiler | `config/compiler/dataset_compiler.gd` | P0-3 |
| 补全的 CompiledDataset | `runtime/core/compiled_data.gd` | P0-3 |
| DamageRequest 参数对象 | `runtime/core/damage_pipeline.gd` | P1-1 |
| deal_damage_v2 入口 | `runtime/core/damage_pipeline.gd` | P1-1 |
| Fingerprint 计算逻辑 | `config/compiler/dataset_compiler.gd` | P1-2 |
| 缓存加载方法 | `config/manifest_loader.gd` | P1-2 |
| load_order 排序逻辑 | `config/manifest_loader.gd` | P1-4 |
| JSON Schema 文件集 | `addons/omnibuff/schemas/*.json` | P1-3 |

### 5.2 文档交付物

| 交付物 | 路径 | 关联工作项 |
|--------|------|-----------|
| Tutorial 8 章 | `addons/omnibuff/tutorial/00_index.md` ~ `07_debug_and_extend.md` | P0-4 |
| JSON Schema 文件 | `addons/omnibuff/schemas/` | P1-3 |
| 策划配置指南 | `addons/omnibuff/docs/designer_guide.md` | P2-4 |
| Changelog | `addons/omnibuff/CHANGELOG.md` | P3-7 |
| 迁移指南 | `addons/omnibuff/docs/migration/v1_to_v2.md` | P3-7 |

### 5.3 测试交付物

| 交付物 | 路径 | 关联工作项 |
|--------|------|-----------|
| condition_type 校验测试 | `tests/rpg/test_condition_type_alignment.gd` | P0-1 |
| ownership_key 边界测试 | `tests/base/test_ownership_key_uniqueness.gd` | P0-2 |
| DatasetCompiler 输出测试 | `tests/rpg/test_dataset_compiler_output.gd` | P0-3 |
| load_order 排序测试 | `tests/rpg/test_manifest_load_order.gd` | P1-4 |
| Fingerprint 缓存测试 | `tests/rpg/test_fingerprint_cache.gd` | P1-2 |
| API v2 兼容测试 | `tests/rpg/test_damage_request_v2.gd` | P1-1 |

## 6. 验收标准

### 6.1 P0 验收标准

- [ ] `enums.json` 的 `condition_type` 包含 `STAT_THRESHOLD`，且所有 `buff_defs` 中使用的 condition_type 值均在枚举中定义
- [ ] validators 对非法 condition_type 值在 strict 模式下报 ERROR
- [ ] entity_id = 65536 / 1000000 时，不同 (bdid, source) 组合的 ownership_key 无冲突
- [ ] `OmniCompiledDataset` 包含 `skill_id_to_int`、`equipment_id_to_int`、`set_bonus` 编译产物
- [ ] BattleExecutor 不再回溯 `sources` 字典，所有数据从 `CompiledDataset` 读取
- [ ] Tutorial 8 章全部交付，每章代码示例可运行
- [ ] 全部 GUT 测试通过（0 fail）

### 6.2 P1 验收标准

- [ ] `deal_damage_v2(DamageRequest)` 可正常调用，`deal_damage_v1` 委托给 v2 且结果一致
- [ ] `CompiledDataset.fingerprint` 非空，相同输入数据产生相同 fingerprint
- [ ] `ManifestLoader.load_cached_or_compile()` 在数据未变时跳过编译
- [ ] JSON Schema 文件可校验 base_demo 和 rpg_tests 数据集通过
- [ ] `load_order` 与 `files[]` 顺序不一致时，加载结果按 `load_order` 决定
- [ ] 全部 GUT 测试通过（0 fail）

### 6.3 通用验收标准

- [ ] 无新增 warning（Godot 编辑器 0 warning）
- [ ] 无 `class_name` 新增（遵循项目约定）
- [ ] 新增公开 API 均在 `omnibuff_singleton.gd` 中注册
- [ ] 新增代码无注释（遵循项目 code style）
