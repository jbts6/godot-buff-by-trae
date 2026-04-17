# OmniBuff：Public API 文档（README + api.md）设计

## 背景

随着功能增多（BONUS_DAMAGE：value/ratio/expr、deal_damage_v1 兼容层、OmniBuff singleton 暴露脚本资源），插件对外接入的“正确姿势”需要被明确写下来，否则：
- 使用方直接写 `class_name`（例如 `OmniExprContext`）会遇到解析时机导致的编译错误
- 使用方直接用位置参数调用 `deal_damage(...)`，未来签名再演进会炸
- 使用方不清楚哪些是稳定 API、哪些是内部实现细节

---

## 目标

1) README 提供 **Quickstart + Stable API 摘要**（短、可复制）
2) `addons/omnibuff/docs/api.md` 提供 **完整 Public API 文档**：
   - 命名空间入口：`OmniBuff` singleton
   - 稳定 API：`DamagePipeline.deal_damage_v1`
   - BONUS_DAMAGE 配置（value/ratio/expr + 不递归 guard）
   - 推荐写法与反例（class_name pitfalls / 位置参数 pitfalls）
3) 文档内容与当前实现保持一致，并约定未来升级时维护位置（变更时更新 api.md + changelog/notes）

---

## 文档范围与结构

### 1) addons/omnibuff/README.md（追加一节）

新增章节：
- **Public API / Stable API（TL;DR）**
  - “不要直接用 class_name，使用 OmniBuff.Xxx/preload”
  - “调用 deal_damage 用 deal_damage_v1”
  - “BONUS_DAMAGE 不递归：filters.require_not_bonus_damage + tags BONUS_DAMAGE”
  - 指向详细文档：`addons/omnibuff/docs/api.md`

README 保持简短：只提供 1-2 段可直接复制的示例。

### 2) addons/omnibuff/docs/api.md（扩写为权威文档）

建议结构：
1. 概览（这是什么、适合谁、版本/兼容声明）
2. Autoload：`OmniBuff` singleton（列出暴露的脚本：BuffCore/DamagePipeline/Replay/...）
3. Stable API
   - `DamagePipeline.deal_damage_v1`：签名、参数解释、示例（命名参数推荐）
4. Event / Buff definitions（面向使用者）
   - BONUS_DAMAGE（value/ratio/expr）
   - require_not_bonus_damage（为何需要、如何使用）
   - tags_mask_any（如何做顺序无关识别、追帧）
5. Pitfalls（常见坑）
   - class_name 解析时机（不要写 OmniExprContext，改用 OmniBuff.ExprContext/preload）
   - 位置参数签名演进（用 deal_damage_v1 或命名参数）
6. Compatibility Notes（简短）
   - deal_damage 新增 is_bonus_damage，但对外推荐 v1

---

## 非目标

- 不写“完整教程/玩法文章”
- 不引入额外文档生成工具链

---

## 验收标准

- README 有一段可复制 Quickstart（能跑通一个最小 deal_damage_v1 + BONUS_DAMAGE 示例）
- api.md 中 Public API、稳定 API、BONUS_DAMAGE 配置、pitfalls 说明完整

