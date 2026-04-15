# OmniBuff “完成”定义 Checklist（Definition of Done）

> 用途：把“完成”的定义写成可逐条勾选的清单，我们按此推进直到你认可为“完成”。
> 说明：每一条都尽量可验证（通过 GUT / demo / 代码结构 / 性能约束检查）。

---

## A. 核心正确性（Buff 生命周期）

- [x] **A1 叠加策略完整**：`REPLACE / ADD_STACK / MULTI_INSTANCE` 行为与 max_stack、ownership_mode 一致（含边界：满层、重复施加、不同来源）。
- [x] **A2 刷新策略完整**：`NONE / RESET_TO_MAX / EXTEND / REFRESH_DURATION`（至少明确实现/不实现的列表，且行为可预测）。
- [x] **A3 到期/持续完整**：`duration.type=TURNS` 会随回合推进递减并到期移除；DOT 与非 DOT 都遵守到期。
- [x] **A4 条件型持续完整**：`WHILE_CONDITION`（例如套装条件）在条件失效时按 policy 正确挂起/移除。
- [x] **A5 主动移除接口稳定**：提供明确 API（如 `remove_by_instance` / `remove_by_id`），并保证撤销 modifier、注销事件、清理 DOT。

## B. 驱散与免疫（可控性）

- [x] **B1 驱散按 Tag**：`dispel_by_tag(tag, include_implicit)` 正确；默认不驱散 `IMPLICIT/PASSIVE`。
- [x] **B2 驱散按来源**：`dispel_by_source(source, include_implicit)` 正确。
- [x] **B3 驱散按类型**：`dispel_by_type(EXPLICIT/IMPLICIT/PASSIVE/AURA)` 正确。
- [x] **B4 不可驱散**：支持 `undispellable`（数据配置 + 运行时遵守）。
- [x] **B5 驱散免疫**：`target_dispel_immunity_mask` 生效且有测试覆盖（免疫时 removed=0）。
- [x] **B6 驱散会清理 DOT**：驱散 debuff 后 DOT 不再 tick（已修复，但需长期回归用例锁死）。

## C. 属性系统（StatCache / Modifiers / Phase）

- [x] **C1 读取路径统一**：热路径属性读取只经 `StatsComponent.get_final(stat_id)`（StatCache）。
- [x] **C2 Dirty 粒度正确**：施加/移除 Buff 仅标脏受影响 stat，不做全量重算。
- [x] **C3 Modifier 语义完整（阶段）**：至少明确并实现以下阶段（或明确不支持并拒绝加载）：
  - [x] BASE（基础覆盖/加成）
  - [x] FLAT（平铺）
  - [x] PERCENT（百分比）
  - [x] FINAL（最终修正）
  - [x] CLAMP（区间裁剪）
- [x] **C4 Operator 完整**：`ADD / MUL / OVERRIDE`（至少对每种 op + phase 的组合给出支持矩阵）。
- [x] **C5 Priority 排序完整**：同一 stat 的 modifier 按 `priority` 稳定排序、可预测。
- [x] **C6 数值边界一致**：遵守 `stat_defs` 的 min/max/clamp 语义，且测试覆盖（特别是 0..1 概率类 stat）。

## D. 事件系统（EventIndex / Triggers）

- [x] **D1 EventIndex 硬约束**：事件触发仅遍历 listeners 子集，不遍历全 buff。
- [x] **D2 filters 完整**：至少支持并测试：`tag_mask_any`、（可选）`source_is_self/target_is_self`、`phase` 等。
- [x] **D3 action 完整**：至少支持并测试：
  - [x] `ADD_BASE_DAMAGE`
  - [x] `APPLY_BUFF`
  - [x] `CHANCE_APPLY_BUFF`（概率）
- [x] **D4 概率可复盘**：事件概率与命中/暴击概率都能通过 seed 回放一致（同输入同输出）。
- [x] **D5 触发链治理**：循环触发检测 + 过深触发链告警/阻断（validators）。

## E. DOT（持续伤害）

- [x] **E1 结算点明确**：默认 `TURN_START` 结算，且数据集与测试一致。
- [x] **E2 按来源独立实例**：同种 DOT 不同来源独立实例（DotInstance），且稳定排序。
- [x] **E3 每跳读取来源属性**：tick 时读取来源 `StatCache`，不遍历来源 buff。
- [x] **E4 DOT 生命周期完整**：remaining_turns 递减到 0 移除（与回合推进一致）。
- [x] **E5 驱散与免疫交互**：驱散/免疫对 DOT 的行为可预测且有整回合集成测试锁死。

## F. DamagePipeline（战斗结算骨架）

- [x] **F1 阶段骨架稳定**：BUILD/BEFORE_DEAL/BEFORE_TAKE/RESOLVE/APPLY/AFTER_DEAL/AFTER_TAKE 阶段顺序与语义稳定。
- [x] **F2 护盾**：SHIELD 先吸收，再扣 HP（有单元测试 + 集成测试）。
- [x] **F3 减伤**：DMG_REDUCE 在 resolve 后、apply 前生效（顺序固定）。
- [x] **F4 命中/暴击**：确定性 RNG，且对旧数据集保持兼容（未启用 HIT_RATE/EVADE 时不改变旧期望）。
- [x] **F5 多段攻击支持**：多段产生多条 DamageTrace，且可断言“不会串段”。

## G. 数据驱动与校验（manifest/enums/defs）

- [x] **G1 manifest 权威**：所有数据文件通过 manifest.files 加载，路径解析稳定。
- [x] **G2 enums 权威**：枚举与 tag 的 bitmask 映射稳定、可追溯。
- [x] **G3 Schema 治理**：深度未知字段治理（JSONPath 指明位置），strict/lenient 可控。
- [x] **G4 错误定位可用**：Issue 包含 file + loc + id + message。

## H. 回放与追帧（Replay/Trace）

- [x] **H1 DamageTrace 完整**：至少记录 turn、atk/def、hit/crit、base/final、tags_mask、triggered_inst_ids、stage_triggers。
- [x] **H2 DotTrace 完整**：至少记录 turn、source/target、read_source_stat/value、ratio、base/final、tags_mask。
- [x] **H3 Debug dump 可读**：提供 range dump，便于多段/多DOT排障。

## I. 测试与回归（GUT）

- [ ] **I1 单元测试覆盖核心机制**：flat/percent、护盾、减伤、命中/暴击、驱散/免疫、DOT。
- [ ] **I2 整回合集成测试**：护盾→三连→每段挂DOT→TurnStart结算→驱散→免疫（全链路）。
- [ ] **I3 数据集隔离**：`data/rpg_tests` 专用于测试，不污染 demo 数据。
- [ ] **I4 Headless/CI 可运行**：提供明确命令与退出码语义（失败退出非 0）。

## J. 性能预算与工程化

- [ ] **J1 性能预算文档**：列出关键操作复杂度（施加/移除/单次伤害/每回合 tick），并给出上限建议（例如 1k buff 级别）。
- [ ] **J2 无全量遍历**：明确禁止点（在代码注释或文档中）并有基本测试/断言避免回归。
- [ ] **J3 内存与对象生命周期**：DotInstance/BuffInst 的创建与清理无泄漏（至少通过“回合推进 + 驱散”测试覆盖）。

## K. 文档（换上下文可用）

- [ ] **K1 README 完整**：安装/启用、OmniBuff 入口、最小示例、DOT TURN_START 语义、测试运行方式。
- [ ] **K2 API 约定写清楚**：runtime dict（stats_by_entity/buff_by_entity）用途、事件 scope 语义等。
- [ ] **K3 版本与兼容策略**：说明对 Godot 版本、GUT 分支、数据 schema_version 的兼容范围。

---

## 我建议的“完成”门槛（可选）

如果你希望有一个明确“过线”的定义，我建议至少满足：
- A（生命周期）≥ A1+A3+A5
- B（驱散/免疫）≥ B1+B4+B5+B6
- C（属性）≥ C1+C2+C3(FLAT/PERCENT)+C4(ADD/MUL)+C6
- D（事件）≥ D1+D2(tag_mask_any)+D3(APPLY_BUFF/CHANCE)+D4
- E（DOT）≥ E1~E5
- F（流水线）≥ F1~F5
- I（测试）≥ I1~I3
- K（文档）≥ K1
