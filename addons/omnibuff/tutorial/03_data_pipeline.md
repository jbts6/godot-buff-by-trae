# 03 — 数据链路：manifest/enums/defs → validate → compile

本章解释 OmniBuff 的“数据驱动”到底是什么：
- 你应该编辑哪些文件？
- 加载时做了哪些校验（validators）？
- 为什么要有 compile（编译产物）这一步？

---

## 1. 数据集（Dataset）的组成

一个数据集至少包含：

- `manifest.json`：入口与文件清单（权威）
- `enums.json`：枚举与 tags 白名单（协议治理核心）
- `stat_defs.json`：属性定义
- `buff_defs.json`：buff 定义（effects + triggers）

示例路径：
- `res://data/base_demo/manifest.json`
- `res://data/rpg_tests/manifest.json`

---

## 2. 一张图看加载链路

```mermaid
flowchart LR
  M[manifest.json] --> L[ManifestLoader.load_dataset_full]
  L --> E[load enums.json]
  L --> S[load sources\n(stat_defs/buff_defs/...)]
  E --> V[Validate.validate_all]
  S --> V
  V -->|issues| OUT[Result.issues]
  V -->|ok| C[DatasetCompiler.compile]
  C --> DS[CompiledDataset]
  DS --> RT[Runtime (Stats/Buff/Damage)]
```

重点：
- **strict=true** 时，重要问题会以 ERROR 阻断（建议生产/CI 使用）
- `compile` 的产物 `ds` 才是运行时核心依赖的唯一数据源

---

## 3. manifest.json：为什么它是“权威入口”

manifest 的价值：
- 让数据集“可组合”（未来可扩展更多源文件）
- 让加载器知道每个文件的 type（用于校验与编译）
- 统一收口错误定位（issues 里能带上 file/loc/id/message）

在代码里你会看到：
- `ManifestLoader.load_dataset_full(...)` 先读 manifest，再按 files 列表加载其它源

---

## 4. enums.json：协议治理与“白名单 DSL”

为什么需要 enums？

因为 buff_defs/stat_defs 本质上在定义一个 DSL（领域语言）：
- event_type/event_phase/action_kind/op_type/apply_phase/stack_mode...

如果没有白名单：
- 配错一个字符串（比如 "AFTER_DEALL"）可能悄悄失效
- 版本升级时也很难做迁移与兼容

因此 OmniBuff 的策略是：
- enums.json 定义 “允许出现的值集合”
- validators 在加载期把错误尽早报出来

---

## 5. validators：为什么要把错误提前到加载期

在 `res://addons/omnibuff/config/compiler/validators.gd` 里，校验会覆盖：
- unknown fields（严格/宽松模式）
- stat 引用是否存在
- 枚举值是否合法
- 某些高风险配置（例如 BONUS_DAMAGE 不递归 guard）是否缺失

优点：
- 你不需要等到运行时打一局才发现“配置没生效”
- 可用于 CI（测试环境严格模式）

---

## 6. compile：为什么要有编译产物（CompiledDataset）

运行时热路径如果直接读 JSON 字典：
- 会频繁做字符串 key 查找
- 字段名变更会影响运行时逻辑
- 很难做后续性能优化

所以 OmniBuff 的边界是：
- compile 层允许读 raw 字段（schema）
- runtime 只读 `CompiledDataset`（index/int 映射）

当前 `CompiledDataset` 仍保存 `Array[Dictionary]`（为了可迭代），但已经建立了关键映射：
- `ds.stat_id("HP") -> int`
- `ds.buff_id("buff_xxx") -> int`

并且 Phase 2 已开始把“派生依赖图”等信息也编译进 ds（derived graph）。

---

## 7. 你在项目里应该怎么组织自己的数据集

建议：
- 先从 `rpg_tests` 复制一份数据集模板
- 先只改 `buff_defs.json`，每加一个能力点就：
  1) 在 UI demo 里做一个 scenario 可复现
  2) 在 tests/rpg 里加一个最小测试

这样你的战斗系统越做越大时，Buff 系统仍然可回归。

---

## 本章小结

你现在应该理解：
- 为什么 manifest/enums/validators/compile 是一条“冷路径”
- 为什么 runtime 不直接读 raw json
- 为什么 enums/validators 能让 DSL 更可靠

下一章我们深入 Stats 系统：缓存、分层、override、breakdown、derived/curve。  
继续阅读：`04_stats_system.md`

