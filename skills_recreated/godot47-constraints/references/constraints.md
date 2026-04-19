# godot47-constraints / references/constraints.md

> 本文件包含 **Godot 4.7 通用硬约束** 的完整版本。适用于本仓库所有模块。

## 1) 开发流程（必须：严格 TDD 双提交）

### 1.1 双提交规则（硬约束）
每个行为变更（新功能 / 修 bug / 重构）必须拆成两个 commit：

**Commit A：RED**
- 仅允许改测试文件：`**/tests/**`
- 必须能在本机跑出 FAIL（**断言失败**；不是解析期错误/语法错误/路径错误）
- commit message：`test(<scope>): <desc> (red)`

**Commit B：GREEN**
- 只写让 RED 测试通过的最小实现（必要重构可以，但不得引入新行为）
- commit message：
  - `feat(<scope>): <desc> (green)`
  - `fix(<scope>): <desc> (green)`
  - `refactor(<scope>): <desc> (green)`

### 1.2 测试运行（硬约束）
- 修改前/后都必须跑测试
- 合并前必须全量跑通

本仓库统一入口（若存在）：`./run_gut_tests.sh`

---

## 2) Godot 4.7 解析期/静态分析硬约束（全仓库强制）

> 目标：避免解析期报错（Cannot infer type / invalid call / preload fail），保证脚本可加载。

### 2.1 禁止使用 `:=`（硬约束）
**原因**：Godot 4.7 对 `:=` 会做解析期类型推断，遇到 `Variant/Dictionary.get()/RefCounted` 等动态值会推断失败并在解析期报错。

- 禁止：
  - `var x := dict.get("a", [])`
  - `var r := some_call_returning_variant()`
- 允许（推荐）：
  - `var x = dict.get("a", [])`
  - 显式类型：`var x: Array = dict.get("a", [])`、`var r: Dictionary = ...`

### 2.2 禁止使用 `has_property()`（硬约束）
**原因**：Godot 4.7 的 `Object/RefCounted` 不存在 `has_property()`。

- 禁止：`obj.has_property("hp")`
- 必须改为：
  - 基于 `get_property_list()` 的检测
  - 或在确定属性存在时使用 `obj.get("hp")`

### 2.3 禁止 Dictionary 点访问（硬约束）
- 禁止：`sr.ok` / `rt.db`
- 必须：`sr.get("ok", false)` / `rt["db"]` / `rt.get("db")`

### 2.4 可空参数（null）规范（强制）
- 允许为 null 的参数必须写成：`func f(x = null, ...)`
- 不要写任何依赖解析期推断的类型标注导致报错的形式

---

## 3) 测试约束（GUT）

### 3.1 基本规则
- 测试脚本必须：`extends GutTest`
- 测试文件建议：`test_*.gd` 放在 `**/tests/**`

### 3.2 防止错误“污染”的 guard 规则
GUT 的 `assert_*` 默认不会中断函数执行。若断言失败后仍访问数组下标，容易把真实失败“污染”为 out-of-bounds。

- 必须在关键点加 guard：
  - `if not ok: return`
  - `if arr.is_empty(): return`

### 3.3 解析期错误的处理方式
若遇到“脚本 preload 失败 / 解析期类型推断错误”，优先新增一个 **preload 编译守卫测试** 来锁定回归：
- 测试中 `preload("res://path/to/script.gd")`
- 若脚本无法解析，测试在加载阶段直接红（并可在 CI/headless 中复现）

---

## 4) 命名规范（强制 / 全仓库）

> 原则：文件/资源 snake_case；类名 PascalCase；常量 SCREAMING_SNAKE_CASE；信号/方法/变量 snake_case。  
> 所有命名必须稳定、可检索、可预测；禁止随意缩写。

### 4.1 文件与资源命名
- `.gd / .tscn / .tres / .res / .json / .md`：一律 `snake_case`
  - 示例：`turn_manager.gd`, `demo_battle.tscn`, `skill_runtime.gd`

### 4.2 类与脚本
- `class_name`：`PascalCase`
  - 示例：`class_name TurnManager`

### 4.3 变量、方法、信号、常量
- 变量：`snake_case`
- 方法：`snake_case`
- signal：`snake_case`
- 常量：`SCREAMING_SNAKE_CASE`
- 私有成员：以 `_` 前缀

### 4.4 Dictionary key 命名
- 字符串 key 一律 `snake_case`（禁止混用 camelCase）
  - 示例：`"skill_id"`, `"caster_id"`, `"predicted_deltas"`

### 4.5 错误码命名（用于 tests/业务分支）
- 错误码字符串：`lower_snake_case`，允许用 `:` 拼接细节
  - 示例：`unknown_skill_id:act_xxx`, `skill_validation_failed:act_xxx`

---

## 5) Agent 交付自检清单（必须）
- [ ] 无新增 `:=`
- [ ] 无新增 `has_property()`
- [ ] 无新增 Dictionary 点访问
- [ ] 新增行为均有 RED→GREEN 两个 commit
- [ ] `./run_gut_tests.sh` 全绿
- [ ] 命名符合本节规范

