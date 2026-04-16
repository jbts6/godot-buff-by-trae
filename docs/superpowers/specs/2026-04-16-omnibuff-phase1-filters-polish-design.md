# OmniBuff Phase 1：Filters 补齐与打磨（设计）

## 背景

当前 Phase 1 Filters 的主干能力已落地并通过测试：
- require_crit / require_hit
- damage_type_any / element_any
- require_shield_absorbed / min_final_damage
- 火焰免疫已升级为 APPLY 阶段：SHIELD = ctx.final_damage（无残留护盾）

但还缺少两类“工程完成度”工作：
1) **覆盖补齐**：skill_id、min_absorbed_shield 的测试与 demo 场景、更多负例
2) **协议治理**：validators/hud/doc 的一致性与边界行为说明

---

## 目标

### 1) Filters 功能补齐

新增/补齐以下 filters 的端到端覆盖（data → runtime → tests → demo → HUD）：

1. `filters.skill_id`
   - 支持单个 skill_id（int）
   - 仅当 `ctx.skill_id` 匹配才触发
2. `filters.min_absorbed_shield`
   - 仅当 `absorbed_shield >= min_absorbed_shield` 才触发
   - 需要明确 meta 缺失时 absorbed=0（不触发）

### 2) 更多负例测试（避免回归）
- skill_id 不匹配时不触发
- min_absorbed_shield 阈值未达到时不触发
- element_any 不匹配时不触发（已隐含，但补一条更直观）

### 3) 协议与可观测性一致性
- validators：
  - skill_id >= 0
  - min_absorbed_shield / min_final_damage >= 0
  - enums 反查错误信息更明确（指出 dataset 的 enums 来源）
- Debug HUD：
  - Listeners 面板对 skill_id / min_absorbed_shield 已能展示（确认格式稳定）
- README：
  - 增加 filters 章节：列出已支持 filters 与它们的“可用阶段”说明（例如 min_final_damage 在 APPLY/AFTER_* 更有意义）

---

## 设计决策与边界行为

### 1) skill_id 的赋值来源
由 `DamagePipeline.deal_damage(..., skill_id=...)` 可选参数写入 `ctx.skill_id`；默认 -1。

约定：
- filters.skill_id 设置后，若 ctx.skill_id 仍为 -1：视为不匹配（不触发）

### 2) min_absorbed_shield 的来源
absorbed_shield 由 APPLY 阶段护盾扣除写入 `ctx.meta["absorbed_shield"]`。

约定：
- 若 meta 不存在：absorbed=0
- `require_shield_absorbed=true` 等价于 `min_absorbed_shield > 0` 的特例（但两者可同时存在）

### 3) 过滤器生效阶段提示
- require_hit/require_crit：在 pipeline precompute 后，所有阶段可用
- damage_type/element/skill_id：ctx 初始化即有，所有阶段可用
- min_final_damage：依赖 resolve/apply 后才稳定，建议用于 APPLY/AFTER_*；若写在 BEFORE_* 可能永远不触发
- absorbed_shield：依赖 APPLY 后才有，建议用于 AFTER_TAKE（或未来新增 AFTER_APPLY）

---

## 验收标准

- [ ] 新增测试：skill_id + min_absorbed_shield 的正反例全部 PASS
- [ ] Demo 新增 2 个 scenario：skill_id gate、min_absorbed_shield gate
- [ ] HUD Listeners 中能看到这两个 filters 的摘要
- [ ] README 更新 filters 支持列表与阶段说明

