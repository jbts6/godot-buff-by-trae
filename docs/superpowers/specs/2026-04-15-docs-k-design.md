# K（文档：换上下文可用）设计（K1~K3）

## 目标

把 checklist 的 K1~K3 收尾到可打勾，让新加入的人“换上下文也能用”：

- **K1 README 完整**：安装/启用、入口、最小示例、DOT TURN_START 语义、测试运行方式
- **K2 API 约定写清楚**：runtime dict（stats_by_entity/buff_by_entity）用途、事件 scope 语义等
- **K3 版本与兼容策略**：Godot 版本、GUT 版本、数据 schema_version 兼容范围

---

## 现状

`addons/omnibuff/README.md` 已包含 K1 绝大部分内容，并且已有 headless 测试跑法。

缺口主要是：
- K2：runtime dict / scope / ctx 字段约定需要“集中、可复制粘贴”说明
- K3：版本兼容策略需要明确“支持范围与升级方式”

---

## 设计（最小改动）

### 1) K1：README 补齐与校对

对 `addons/omnibuff/README.md`：
- 校对“测试目录结构”部分，与你最新的 tests/base/tests/rpg 结构对齐
- 确保 headless 跑法与 run_gut_tests.sh 参数一致

### 2) K2：增加 `docs/api.md`（单文件权威）

新增文档 `addons/omnibuff/docs/api.md`（或 `docs/omnibuff-api.md`，本轮放在插件目录更就近）包含：
- Dataset/manifest/enums/validate/compile 的标准调用链
- runtime dict 结构：`stats_by_entity`/`buff_by_entity` 的必备键与类型
- DamageContext（ctx）在 pipeline/事件中的关键字段（atk/def/hit/crit/base/final/tags_mask）
- 事件 scope 语义：`SELF/SOURCE/TARGET` 如何解析
- Replay trace 作为调试输出，不驱动逻辑

### 3) K3：版本与兼容策略（README 新增一节）

在 README 增加 “Compatibility” 小节：
- Godot：以 4.7 为基线（CI/headless 也按此）
- GUT：vendor 到 `res://addons/gut/`，以仓库版本为准
- 数据 schema_version：当前为 1；升级策略：通过 `OmniMigrate.migrate` 在线迁移（不写回源文件）
- tags.code 作为兼容契约：只增不复用

---

## 验收标准

- README 更新后能作为“一页入门”
- api.md 可作为“复制粘贴模板”与“接口契约”
- checklist：K1~K3 勾选为完成并提交

