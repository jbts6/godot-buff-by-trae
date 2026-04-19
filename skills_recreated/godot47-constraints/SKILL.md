---
name: godot47-constraints
description: Godot 4.7 项目开发硬约束（通用）。只要用户要写/改 Godot GDScript、修解析期报错、写 GUT 测试、做插件/Autoload/资源命名，就必须启用本 skill；强制 TDD 双提交（RED→GREEN），并禁止 :=、has_property、Dictionary 点访问等易踩坑写法。
---

# Godot 4.7 通用开发约束（AI Agent）

你正在为一个 **Godot 4.7** 项目编写/修改代码与测试。你必须遵守以下硬约束。

## 1) 必读：完整约束

在开始任何代码改动前，先阅读并遵守：
- `references/constraints.md`

> 说明：本 SKILL.md 保持“可触发的短描述 + 入口”，详细规则放在 references 里，避免过长。

## 2) 触发条件（你必须主动启用本 skill 的场景）
只要用户的需求涉及以下任意一项，你都必须使用本 skill：
- “写/改 Godot 代码”“GDScript 报错”“Cannot infer type”“解析期报错”“脚本 preload 失败”
- “写 GUT 测试/补测试/跑 headless 测试”
- “新增插件/Autoload/Editor Dock/资源导入/场景脚本”
- “整理命名规范/目录结构/错误码规范”

## 3) 最重要的三条（摘要）
1. **严格 TDD 双提交**：先 RED（只改 tests，且能 FAIL），再 GREEN（最小实现让 tests PASS）。
2. **全仓库禁止 `:=`**：避免 Godot 4.7 解析期类型推断失败。
3. **禁止 `has_property()` 与 Dictionary 点访问**：用 `get_property_list()` / `get()` / `[]` 替代。

## 4) 快速自检（每次交付前必须满足）
- 无新增 `:=`
- 无新增 `has_property()`
- 无新增 Dictionary 点访问（`d.foo`）
- 有 RED→GREEN 两个 commit
- `./run_gut_tests.sh` 全绿

## 5) 建议测试用例（用于评估本 skill 是否生效）
**用例 1：**
> “我在 Godot 4.7 里遇到 Cannot infer type 的解析期报错，帮我修并补 GUT 测试。”

**用例 2：**
> “帮我给某个模块补齐单元测试，并要求严格 TDD 双提交。”

