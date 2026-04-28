# OmniBuff 成熟化项目实施计划（Maturity Plan）

> 创建日期：2026-04-28
> 状态：已批准
> 版本：1.0

---

## 1. 项目阶段划分

本项目分为 **4 个阶段**，按优先级递减推进：

| 阶段 | 名称 | 核心目标 | 工作项 |
|------|------|----------|--------|
| Phase A | 紧急修复 | 消除已知 Bug 和架构债务 | P0-1, P0-2 |
| Phase B | 架构补全 | DatasetCompiler 编译链路闭合 | P0-3 |
| Phase C | 文档与基础设施 | Tutorial + API 版本化 + Fingerprint + Schema | P0-4, P1-1, P1-2, P1-3, P1-4 |
| Phase D | 体验与优化 | HUD 增强 / 性能 / Mod / 策划指南等 | P2-*, P3-* |

---

## 2. Phase A：紧急修复

### 2.1 P0-1：condition_type 枚举与实现对齐

**问题**：enums.json 定义 `condition_type = ["HAS_TAG", "STAT_GE", "EQUIP_SET_COUNT_GE"]`，但 buff_defs 实际使用 `"STAT_THRESHOLD"`（不在枚举中）。

**任务分解**：

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| A1 | 修正 enums.json：将 condition_type 改为 `["STAT_THRESHOLD", "EQUIP_SET_COUNT_GE", "HAS_TAG", "STAT_GE"]` | `data/base_demo/enums.json` |
| A2 | 在 validators 中新增 condition_type 枚举合法性校验 | `config/validators.gd` |
| A3 | 新增测试：非法 condition_type 在 strict 下报 ERROR | `tests/rpg/test_condition_type_alignment.gd` |
| A4 | 验证 base_demo 和 rpg_tests 数据集在 strict=true 下加载 0 error | 手动验证 |

**预期效果**：枚举定义与实际使用一致；编译期可捕获非法 condition_type。

**风险评估**：
- 风险：修改 enums.json 可能影响现有 validators 的枚举校验逻辑
- 应对：修改后立即运行全量 GUT 测试验证

### 2.2 P0-2：ownership_key 哈希冲突修复

**问题**：`_ownership_key` 使用 `bdid << 16 ^ source`，entity_id > 65535 时冲突。

**任务分解**：

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| A5 | 替换哈希函数为 `int(bdid) * 1000003 ^ int(source)` | `runtime/core/buff_core.gd` |
| A6 | 新增边界测试：entity_id = 65535/65536/1000000 时的唯一性 | `tests/base/test_ownership_key_uniqueness.gd` |
| A7 | 验证现有数据集所有 ownership_key 映射关系不变 | 手动验证 |

**预期效果**：消除 entity_id > 65535 时的 ownership 冲突。

**风险评估**：
- 风险：哈希函数变更可能导致同一 (bdid, source) 产生不同的 ownership_key，影响已有存档/回放
- 应对：由于项目尚在开发期（无生产存档），直接替换即可；若需兼容，可在 CompiledDataset 中记录哈希函数版本

---

## 3. Phase B：架构补全

### 3.1 P0-3：DatasetCompiler 编译补全

**问题**：skill_defs / equipment / set_bonus / damage_pipeline 未编译到 CompiledDataset；buff_defs 子结构仍为 Dictionary 直通。

**任务分解**：

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| B1 | CompiledDataset 新增字段：`skill_id_to_int`, `skill_defs_compiled`, `equipment_id_to_int`, `equipment_defs_compiled`, `set_bonus_compiled`, `pipeline_stages_compiled` | `runtime/core/compiled_data.gd` |
| B2 | DatasetCompiler 新增 skill 编译：构建 id_to_int 映射 + 紧凑数组 | `config/compiler/dataset_compiler.gd` |
| B3 | DatasetCompiler 新增 equipment 编译 | 同上 |
| B4 | DatasetCompiler 新增 set_bonus 编译 | 同上 |
| B5 | DatasetCompiler 新增 damage_pipeline 编译：阶段定义转为 PackedInt32Array | 同上 |
| B6 | buff_defs 子结构预编译：effects/triggers/dot 的枚举字符串预转为 int code，tags 预转为 bitmask | 同上 |
| B7 | BattleExecutor 迁移：从 sources 字典读取改为从 CompiledDataset 读取 | `runtime/core/battle_executor.gd` |
| B8 | BuffCore 适配：bd["effects"] 等字典访问改为编译产物访问 | `runtime/core/buff_core.gd` |
| B9 | DamagePipeline 适配：pipeline 阶段定义从 CompiledDataset 读取 | `runtime/core/damage_pipeline.gd` |
| B10 | 新增测试：DatasetCompiler 输出完整性校验 | `tests/rpg/test_dataset_compiler_output.gd` |
| B11 | 全量 GUT 回归验证 | 手动验证 |

**预期效果**：运行时核心零 sources 字典回溯；buff_def 子结构访问从 O(1) 字典查找升级为 O(1) 数组索引。

**风险评估**：
- 风险：B6（buff_defs 子结构预编译）涉及 buff_core.gd 全文适配，改动量大（2144 行中约 40% 需修改）
- 应对：分两步走——先完成 B1-B5（新增编译字段），再逐步完成 B6-B9（替换访问方式）；每步后运行全量测试
- 风险：编译产物格式变更可能影响现有测试中直接访问 sources 字典的代码
- 应对：保留 sources 字典作为"调试后备"（不删除），新增 compiled 访问路径；测试逐步迁移

---

## 4. Phase C：文档与基础设施

### 4.1 P0-4：Tutorial 教程交付

**任务分解**：

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| C1 | 编写 00_index.md：教程导航 + 设计哲学概述 | `addons/omnibuff/tutorial/00_index.md` |
| C2 | 编写 01_why_buff.md：为什么需要 Buff 系统 + "万物皆 Buff" 思想 | `addons/omnibuff/tutorial/01_why_buff.md` |
| C3 | 编写 02_data_driven.md：数据驱动架构 + manifest/enums/defs 关系 | `addons/omnibuff/tutorial/02_data_driven.md` |
| C4 | 编写 03_stats.md：属性系统 + StatCache + 脏标记 + modifier 聚合 | `addons/omnibuff/tutorial/03_stats.md` |
| C5 | 编写 04_buff_lifecycle.md：Buff 生命周期 + 叠层 + 驱散 + 免疫 | `addons/omnibuff/tutorial/04_buff_lifecycle.md` |
| C6 | 编写 05_damage_pipeline.md：伤害管线 6 阶段 + 事件触发 | `addons/omnibuff/tutorial/05_damage_pipeline.md` |
| C7 | 编写 06_dot_and_turns.md：DOT 语义 + 回合推进 + TurnComponent | `addons/omnibuff/tutorial/06_dot_and_turns.md` |
| C8 | 编写 07_debug_and_extend.md：Debug HUD + 扩展指南 | `addons/omnibuff/tutorial/07_debug_and_extend.md` |

**预期效果**：新用户 30 分钟内理解设计哲学并跑通第一个示例。

**风险评估**：
- 风险：Tutorial 代码示例可能因后续 API 变更而过时
- 应对：代码示例从现有 demo/test 中提取（非手写），减少维护成本

### 4.2 P1-1：API 版本化与兼容层规范化

**任务分解**：

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| C9 | 新增 DamageRequest 类（Dictionary 封装 + 类型提示） | `runtime/core/damage_pipeline.gd` |
| C10 | 新增 deal_damage_v2(req) 入口，v1 和原版均委托给 v2 | 同上 |
| C11 | 统一 demo/test 代码使用 v2 入口 | `demo/*.gd`, `tests/**/*.gd` |
| C12 | 更新 api.md：v2 签名 + 版本化策略说明 | `addons/omnibuff/docs/api.md` |
| C13 | 新增测试：v2 与 v1 结果一致性 | `tests/rpg/test_damage_request_v2.gd` |

**预期效果**：API 演进不再需要不断增加参数；旧代码不会被突然破坏。

**风险评估**：
- 风险：修改 50+ 处调用点可能引入回归
- 应对：v1 委托给 v2 保证结果一致；分批迁移（先迁移 tests，再迁移 demo）

### 4.3 P1-2：Fingerprint 缓存校验实现

**任务分解**：

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| C14 | 实现 content_hash 计算：按 manifest.build.fingerprint.files 列表计算 SHA-256 | `config/compiler/dataset_compiler.gd` |
| C15 | 写入 CompiledDataset.fingerprint | `runtime/core/compiled_data.gd` |
| C16 | 新增 ManifestLoader.load_cached_or_compile() | `config/manifest_loader.gd` |
| C17 | 缓存文件存储为 .res 格式 | 同上 |
| C18 | 新增测试：fingerprint 一致性 + 缓存命中/失效 | `tests/rpg/test_fingerprint_cache.gd` |

**预期效果**：大型数据集加载从 O(N) 编译降为 O(1) 反序列化。

**风险评估**：
- 风险：缓存文件跨 Godot 版本/跨平台可能不兼容
- 应对：fingerprint 不匹配时自动重新编译（降级策略）

### 4.4 P1-3：JSON Schema 正式定义

**任务分解**：

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| C19 | 编写 manifest.schema.json | `addons/omnibuff/schemas/manifest.schema.json` |
| C20 | 编写 enums.schema.json | `addons/omnibuff/schemas/enums.schema.json` |
| C21 | 编写 stat_defs.schema.json | `addons/omnibuff/schemas/stat_defs.schema.json` |
| C22 | 编写 buff_defs.schema.json | `addons/omnibuff/schemas/buff_defs.schema.json` |
| C23 | 编写 skill_defs.schema.json | `addons/omnibuff/schemas/skill_defs.schema.json` |
| C24 | 编写 damage_pipeline.schema.json | `addons/omnibuff/schemas/damage_pipeline.schema.json` |
| C25 | 编写 set_bonus.schema.json | `addons/omnibuff/schemas/set_bonus.schema.json` |
| C26 | 验证 Schema 可校验现有数据集通过 | 手动验证 |

**预期效果**：数据配置有机器可校验的协议定义；IDE 可提供自动补全。

**风险评估**：
- 风险：GDScript 生态缺少 JSON Schema 校验库
- 应对：本阶段仅提供 Schema 文件供外部工具（VS Code / ajv-cli）校验；Godot 内校验仍用现有 validators

### 4.5 P1-4：load_order 排序逻辑实现

**任务分解**：

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| C27 | ManifestLoader.load_dataset_full() 中按 load_order 对 files[] 重排序 | `config/manifest_loader.gd` |
| C28 | load_order 缺失时回退到 files[] 原始顺序 | 同上 |
| C29 | 新增测试：load_order 与 files[] 顺序不一致时验证 | `tests/rpg/test_manifest_load_order.gd` |

**预期效果**：manifest 的 load_order 声明生效。

**风险评估**：极低风险，仅影响加载顺序。

---

## 5. Phase D：体验与优化（后续迭代）

Phase D 包含 P2 和 P3 工作项，本计划仅列出概要，详细任务分解在 Phase C 完成后制定。

| 工作项 | 概要 |
|--------|------|
| P2-1 Debug HUD 交互式增强 | 可编辑 Stat + Buff 施加/移除 + 事件时间线 + 回合快照 |
| P2-2 跨平台确定性 RNG | 定点数运算 + 跨平台一致性测试 |
| P2-3 Scenario 数据驱动化 | Scenario JSON schema + ScenarioRunner + 自动扫描 |
| P2-4 策划配置指南 | 配方索引 + 常见错误排查 + 枚举中文速查 |
| P3-1 BuffDef 紧凑数组 | PackedInt32Array + 偏移量访问 |
| P3-2 派生属性优化 | 脏源子集重算 |
| P3-3 Mod 覆盖系统 | load_dataset_with_mods + 冲突日志 |
| P3-4 性能基准 | benchmark_scenario + 耗时统计 |
| P3-5 CSV 解析器增强 | RFC 4180 + BOM + 注释行 |
| P3-6 Bootstrap 合并 | 合并到 Singleton + 移除 Bootstrap |
| P3-7 Changelog | CHANGELOG.md + 迁移指南 |
| P3-8 API 文档对齐 | 一致性检查脚本 + 统一示例 |
| P3-9 HUD 枚举反查优化 | EnumsRuntime reverse_map |

---

## 6. 资源分配

### 6.1 人力分配

| 角色 | 职责 | 分配 |
|------|------|------|
| 核心开发 | 架构补全 + Bug 修复 + API 版本化 | 全程 |
| 文档编写 | Tutorial + Schema + 策划指南 | Phase C 为主 |
| 测试保障 | 新增测试 + 回归验证 | 每阶段末 |

### 6.2 依赖关系

```
Phase A (P0-1, P0-2)
    ↓
Phase B (P0-3) ← 依赖 Phase A 的 enums 修正
    ↓
Phase C (P0-4, P1-1~P1-4) ← P0-4 可与 P1 并行
    ↓
Phase D (P2-*, P3-*) ← 依赖 Phase B 的编译产物格式
```

关键依赖：
- P0-3（DatasetCompiler）依赖 P0-1（condition_type 对齐），因为编译期需要正确的枚举映射
- P1-1（API 版本化）依赖 P0-3（编译产物格式稳定后才能定义 v2 签名）
- P0-4（Tutorial）与其他任务无硬依赖，可并行推进

---

## 7. 风险评估与应对策略

| 风险 | 概率 | 影响 | 应对策略 |
|------|------|------|----------|
| DatasetCompiler 编译补全改动量大，引入回归 | 高 | 高 | 分步实施：先新增编译字段（不删旧路径），再逐步迁移访问方式；每步后全量测试 |
| buff_defs 子结构预编译导致 buff_core.gd 大面积修改 | 高 | 中 | B6 步骤可推迟到 Phase D（P3-1），Phase B 先完成新增编译字段 |
| Tutorial 代码示例因 API 变更过时 | 中 | 低 | 代码示例从 demo/test 提取而非手写；API 稳定后再编写 Tutorial |
| Fingerprint 缓存跨版本不兼容 | 低 | 中 | fingerprint 不匹配时自动重新编译（降级策略） |
| JSON Schema 与 validators 规则不一致 | 中 | 低 | Schema 以 enums.json 为权威源；validators 逻辑不变 |
| ownership_key 哈希变更影响回放一致性 | 低 | 高 | 项目尚在开发期无生产存档；若需兼容可在 CompiledDataset 中记录哈希版本 |

---

## 8. 验收检查点

| 检查点 | 阶段 | 验收内容 |
|--------|------|----------|
| CP-1 | Phase A 完成后 | enums.json condition_type 对齐 + ownership_key 无冲突 + 全量 GUT 通过 |
| CP-2 | Phase B 完成后 | CompiledDataset 包含 skill/equipment/set_bonus/pipeline 编译产物 + BattleExecutor 零 sources 回溯 + 全量 GUT 通过 |
| CP-3 | Phase C 完成后 | Tutorial 8 章交付 + deal_damage_v2 可用 + fingerprint 非空 + JSON Schema 校验通过 + load_order 生效 + 全量 GUT 通过 |
| CP-4 | Phase D 完成后 | 按各工作项验收标准逐项检查 |
