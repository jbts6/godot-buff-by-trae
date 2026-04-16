# OmniBuff Phase 0（Demo-only）版本规划设计（回顾 + 剩余计划）

## 目标

Phase 0 的目标是把当前 OmniBuff 系统落成“**可被设计/QA/程序共同使用的交互式调试与回归平台**”，核心交付物是：

1) `buff_ui_demo`：Scenario Runner（覆盖 `tests/rpg` 的主要能力点）
2) Debug HUD：可视化查看 Stats/Buffs/Dots/Listeners/StatMods，并能复制结构化 dump
3) 配套文档与校验：减少“看代码才知道”的成本、减少数据错误进入运行期

约束：**只服务 Demo**（不接入主游戏架构/网络/预测）。

---

## 现状回顾（已完成）

> 以下以功能点为主；具体提交可在 git log 中查阅。

### A. `buff_ui_demo` Scenario Runner
- UI demo 已重构为 scenario runner：dataset 下拉 + scenario 列表 + run selected/run all + 日志
- rpg_tests 场景已大幅覆盖并持续补齐
- 修复：单体 scenario 也会构建 runtime（否则 HUD entity list 为空）

### B. 日志可导出
- UI demo 增加“复制日志”按钮（内部 log buffer，避免 RichTextLabel.text 为空的问题）

### C. Debug HUD（Demo-only）
- 已集成到 buff_ui_demo：按钮开关、runtime 注入、默认选中 attacker/最小 id
- Tabs：
  - Stats：常用 stat 最终值
  - Buffs：buff 实例列表（对 DOT turns 显示 N/A(DOT)，避免误读）
  - Dots：DotInstance 权威 turns/stacks（并写入 dump）
  - Listeners：按 event_type/event_phase 分组 + last_triggered_inst_ids
  - StatMods：按 stat 分组展示 modifiers_by_stat，并可从 source_inst_id 反查 buff_id
- Copy dump 已包含 stats/buffs/dots/listeners/stat_mods

### D. DOT 语义（为测试与 Demo 统一）
- DotInstance 独立于 BuffInst，并明确 turns 权威来自 DotInstance
- APPLY_BUFF/CHANCE_APPLY_BUFF 支持 `add_stacks`
- DOT 叠层/跨来源总上限/满层刷新语义已落地并通过测试

---

## 剩余范围（Phase 0 待完成）

### 1) Debug HUD：Dump 结构化与长度控制（中优先级）
问题：目前 dump 是拼接文本，内容增多后会变长、难以阅读/贴 issue。

目标：
- 结构化 sections 顺序固定：`[Stats]` → `[StatMods]` → `[Buffs]` → `[Dots]` → `[Listeners]` → `[RecentTraces(optional)]`
- 统一单行格式（便于 grep）
- 加长度上限（例如 20k 字符），超出部分截断并提示 “(truncated)”

### 2) Demo 体验：HUD 自动选中（中优先级）
目标：
- scenario run 完成后，HUD 自动选中 attacker/defender（已有 preferred_entities）
- 对 AOE 场景：可选默认选中第一个 target（或提供下拉快速切换）

### 3) Validate/Lint（Phase 0，低-中优先级）
目标：
- 对常用 action.kind 做字段要求矩阵，并输出更可读的错误提示
- 对 listeners 过宽、缺 require_hit 等给出 lint warning

### 4) 文档：调试工作流与 dump 规范（低优先级）
目标：
- “复现→运行 scenario→打开 HUD→复制日志→复制 dump→定位 listeners/DOT/驱散/免疫”的固定流程
- dump 格式的推荐贴法

---

## 不在 Phase 0 的内容（明确不做）
- 主游戏集成（Autoload、实体注册表、网络同步）
- 回滚/预测、观战快照
- 策划编辑器（GUI 数据编辑器）
- 高级脚本化（Lua/DSL）

---

## 验收标准（Phase 0 完成态）

- [ ] 任意一个 rpg_tests 场景可在 UI demo 里一键运行并复现关键现象
- [ ] HUD 能解释：
  - “我身上有什么 buff/dot？”
  - “哪个 listener 会触发？最近一次触发命中了谁？”
  - “为什么 ATK/HP 是这个值？哪些 modifier 贡献了它？”
- [ ] 能一键复制日志与结构化 dump，贴到 issue 后别人无需复现也能定位 80% 问题

