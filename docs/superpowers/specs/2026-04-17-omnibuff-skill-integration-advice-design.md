# OmniBuff：技能系统接入建议（补充文档）设计

## 背景

你接下来会继续开发技能与战斗系统。OmniBuff 侧目前已支持：
- `DamagePipeline.deal_damage(..., roll_key, skill_id, damage_type, element, is_bonus_damage)`
- 事件 filters：`skill_id / damage_type_any / element_any / require_hit / require_crit / require_not_bonus_damage`
- Replay 记录 `roll_key`，用于解释/回放命中/暴击确定性

因此“技能系统接入”最关键的是：**在上层把 skill 的信息稳定地注入到 DamageContext（skill_id/damage_type/element/tags_mask/roll_key）**，并形成约定，保证可复盘、可调试、可扩展。

## 目标

在 `addons/omnibuff/docs/integrator_guide.md` 新增章节：
**《9. 技能系统接入建议》**，包含：

1) **字段约定与推荐值域**
- `skill_id`：用于 filters.skill_id（建议使用你自己的“技能编译表”的 int id）
- `damage_type` / `element`：用于 filters.damage_type_any / element_any（建议与 enums.json 一致，保持 int code 稳定）
- `tags_mask`：用于 filters.tag_mask_any 与 replay/区分 bonus hit（建议用 tags 组合）

2) **roll_key 约定（确定性核心）**
- roll_key 用于命中/暴击与概率事件的确定性；必须在多段、多目标、追加伤害时做到“每个独立结算点唯一”
- 给出推荐生成规则模板（不依赖随机数、纯函数）

3) **多段/多目标/投射物的组织建议**
- 多段：每段一次 `deal_damage`，roll_key 自增或按 hit_index 编码
- 多目标：目标排序稳定（eid 升序），roll_key = base + target_index*100 + hit_index
- 追加伤害：is_bonus_damage=true；同时 roll_key 使用单独的 namespace（避免与 base hit 冲突）

4) **完整示例**
给出一个可复制的“技能实例”伪实现（GDScript），覆盖：
- 单次施放：对多目标（ALL）多段（3 hit）
- 每段传入：skill_id / damage_type / element / tags_mask / roll_key
- 其中一段触发 bonus damage（通过 Buff action BONUS_DAMAGE 或技能脚本直接调用）时如何避免递归

5) **与现有文档互链**
- 在 integrator_guide 的该章节引用 `schema_reference.md` 的 recipes（BONUS_DAMAGE guard 等）
- 必要时在 `api.md` 的“扩展能力索引”里补 1-2 行指向该章节

## 非目标

- 不引入新的技能系统 runtime 类型（Phase 3 才考虑 skill instance context）
- 不新增新的 enums（本章只做“如何使用现有字段”的建议）

## 验收标准

- [ ] integrator_guide 新增完整章节，包含 roll_key 模板与完整示例代码
- [ ] 文档解释清楚 is_bonus_damage 与 require_not_bonus_damage 的关系
- [ ] 文档解释清楚多段/多目标时 roll_key 的稳定性与目标排序要求

