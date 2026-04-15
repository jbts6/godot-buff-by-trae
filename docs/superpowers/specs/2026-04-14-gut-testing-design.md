# GUT 自动化测试集成设计（OmniBuff）

## 背景与目标

当前 demo 的验证主要依赖肉眼观察控制台输出，容易误判、不可回归、难以持续集成。需要引入自动化测试：

1. **可重复**：同一版本、同一输入下结果一致
2. **可回归**：改动后快速发现破坏行为
3. **可脚本化**：支持 headless/CI 命令行运行
4. **最小侵入**：不要求重构核心运行时，只补充测试入口与断言

选择方案：引入第三方测试库 **GUT（Godot Unit Test）**。

---

## 范围（In Scope）

### 1) 第三方库集成（Vendor）

将 GUT 以“拷贝 vendor 代码”的方式放入项目：

- 路径：`res://addons/gut/`
- 来源：`https://github.com/bitwes/Gut`（只拷贝 `addons/gut` 子目录）

理由：
- 真实项目常见做法（避免编辑器 AssetLib/缓存问题）
- headless 环境可直接执行 `addons/gut/gut_cmdln.gd`
- 与本项目“Autoload 预加载 bootstrap”策略兼容

### 2) 测试目录与命名约定

- 测试目录：`res://addons/omnibuff/tests/`
- 测试脚本：`test_*.gd`（遵循 GUT 约定）
- 共享测试工具：
  - `res://addons/omnibuff/tests/helpers/`（如 entity 构造、dataset 加载等）

### 3) headless 运行命令（开发/CI）

在项目根目录（含 `project.godot`）执行：

```bash
godot --headless --import --quit
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://addons/omnibuff/tests -gexit
```

说明：
- 第一行用于生成/刷新导入缓存（CI/新环境必需）
- `-gexit`：用例失败时退出码非 0，便于 CI 判定失败

### 4) 最少用例集（必须覆盖）

**用例 1：多段攻击（递增 base_damage）**
- 构造 attacker/defender + runtime（stats_by_entity/buff_by_entity）
- 三段 base_damage = `[12,14,18]`
- 断言每段 final_damage 对应递增（避免串段执行）
- 断言 defender HP 结算结果符合预期

**用例 2：防守方 DEF Buff 生效**
- defender 添加 `buff_def_up_20_3t`（DEF+20）
- 使用与用例1相同的三段攻击
- 断言每段 final_damage 明显下降，且下降幅度符合 `final = base + atk - def`

**用例 3：DOT 多来源独立实例 + trace 覆盖**
- 施法者 301/302 对同目标施加 DOT
- 执行 TurnEnd tick
- 断言产生两条 DotTrace（source_entity_id 分别为 301/302）
- 断言每条 DotTrace 中 `source_stat_value` 与预期一致

---

## 非目标（Out of Scope）

- 不实现完整战斗系统/技能系统执行器（仍用测试 helper 直接调用 pipeline/core）
- 不在本阶段把 demo_runner 的所有逻辑迁移为“可配置战斗脚本”
- 不引入额外的 CI 配置文件（可选后续补充 GitHub Actions）

---

## 风险与对策

1) **Godot 全局类表/缓存导致解析期找不到 class_name**
- 对策：
  - 保留 `OmniBuffBootstrap` Autoload 的 preload 兜底
  - 测试脚本内对关键 helper/核心类尽量使用 `preload("res://...")`

2) **第三方库升级带来不兼容**
- 对策：
  - vendor 固定版本（以 commit hash 记录在 README 或注释）
  - 后续需要升级时，通过替换 `addons/gut/` 并跑回归用例

---

## 验收标准

- GUT 能在 headless 下运行，并输出清晰 pass/fail
- 至少 3 个用例全部通过
- 任一断言失败时，命令行退出码非 0

