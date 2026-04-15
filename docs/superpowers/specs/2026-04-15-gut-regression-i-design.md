# I（测试与回归：GUT）设计（最小收尾）

## 目标（本轮最小集）

把 checklist 的 I1~I4 收尾到可打勾：

- **I1 单元测试覆盖核心机制**：确保核心机制各有回归用例（现状已有），补齐“索引/说明”与缺口用例（若发现）。
- **I2 整回合集成测试**：确保存在并稳定锁死“护盾→三连→挂DOT→TurnStart结算→驱散→免疫”全链路（现状已有 `test_full_turn_script_battle.gd`）。
- **I3 数据集隔离**：确保 rpg_tests 作为测试数据集，不依赖/不污染 base_demo（除共享 `enums.json` 这种契约文件）；并用测试锁死 manifest 引用边界。
- **I4 Headless/CI 可运行**：`run_gut_tests.sh` 命令正确使用 `GODOT_BIN`，并且失败退出非 0（CI 可依赖）。

> 原则：以“补齐治理与防回归”为主，避免大规模重构现有测试。

---

## 现状盘点（已具备）

### I1（单元测试）
当前已经覆盖：
- stat/percent/clamp/priority：`tests/rpg/test_stat_*`
- 护盾：`tests/rpg/test_shield_absorb.gd`
- 减伤：`tests/rpg/test_damage_reduction.gd`
- 命中/暴击确定性：`tests/rpg/test_hit_and_crit_deterministic.gd` + `test_hit_crit_determinism.gd`
- 驱散/免疫：`tests/rpg/test_dispel_*` + `test_undispellable_and_immunity.gd`
- DOT：E1/E2 一系列 tests + `test_dot_multi_source_trace.gd`

### I2（整回合集成）
`tests/rpg/test_full_turn_script_battle.gd` 已覆盖并已为 E1 “按来源合并”语义更新断言。

### I4（Headless 脚本）
`run_gut_tests.sh` 已存在，但需要确保两处调用都使用 `${GODOT_BIN}`（当前第二次调用硬编码了 `godot`）。

---

## 本轮新增/调整点

### 1) I3：数据集隔离的“边界测试”
新增 GUT 用例：
- 断言 `data/rpg_tests/manifest.json` 的 `files[].path`：
  - 只允许指向 `res://data/rpg_tests/` 子路径
  - 唯一例外允许 `../base_demo/enums.json`（共享契约）
- 断言 `data/base_demo/manifest.json` 不引用 `../rpg_tests/` 之类路径

### 2) I4：修复 headless 脚本
修改 `run_gut_tests.sh`：
- 第二次执行也用 `"${GODOT_BIN}" --headless -s ...`（不再硬编码 `godot`）
- 保持 `set -euo pipefail` 与 `-gexit`，确保失败退出非 0

### 3) 文档化（可选但推荐）
在 `addons/omnibuff/README.md` 补一段“CI 跑法”：
- `GODOT_BIN=... ./run_gut_tests.sh`
- 说明退出码语义

---

## 验收标准

- 新增 I3 测试通过
- `run_gut_tests.sh` 在本地 headless 可跑，且失败退出非 0
- checklist：I1~I4 勾选为完成并提交

