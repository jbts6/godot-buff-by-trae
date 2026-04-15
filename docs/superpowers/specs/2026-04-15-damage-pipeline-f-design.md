# F（DamagePipeline 战斗结算骨架）设计（最小收尾）

## 目标

把 checklist 中 F 模块（F1~F5）收尾到**可打勾**：

- F1 阶段骨架稳定（阶段存在且语义固定）
- F2 护盾吸收正确
- F3 减伤顺序正确（resolve 后、apply 前）
- F4 命中/暴击确定性 RNG 且兼容旧数据集
- F5 多段攻击不串段（多段产生多条 DamageTrace，结果可断言）

> 本轮选择“最小收尾”：在现有实现与用例基础上，仅补 1 个专门 GUT 用例锁死 F1（阶段存在 + trace 字段完整），并同步更新 checklist 勾选 F1~F5。

---

## 现状（已具备的实现）

`addons/omnibuff/runtime/core/damage_pipeline.gd` 已实现固定阶段：

1) BUILD（attacker）
2) BEFORE_DEAL（attacker）
3) BEFORE_TAKE（defender）
4) RESOLVE（命中/暴击/基础公式）
5) APPLY（attacker + defender）
6) AFTER_DEAL（attacker）
7) AFTER_TAKE（defender）

并在 `Replay.trace_damage` 中记录：
- base_damage / final_damage / tags_mask / hit / crit
- stage_triggers（按阶段收集的 inst_id 列表）

---

## 现状（已具备的测试覆盖）

以下用例已经覆盖 F2~F5 的核心语义：

- F2 护盾：`addons/omnibuff/tests/rpg/test_shield_absorb.gd`
- F3 减伤：`addons/omnibuff/tests/rpg/test_damage_reduction.gd`
- F4 命中/暴击确定性：`addons/omnibuff/tests/rpg/test_hit_and_crit_deterministic.gd` + `test_hit_crit_determinism.gd`
- F5 多段攻击：`addons/omnibuff/tests/test_multihit_attack.gd`（base_demo 数据集）

缺口主要是：
- **F1 没有一个“专门用例”锁死阶段存在性与追帧结构**（虽然其它用例间接依赖阶段流程）

---

## 本轮新增的最小用例（补齐 F1）

新增 GUT：`test_damage_pipeline_stage_traces_present.gd`

断言目标：
- 运行一次 `deal_damage` 后：
  - `replay.damage_traces.size() == 1`
  - `DamageTrace.stage_triggers` 至少包含以下 key：  
    `BUILD/BEFORE_DEAL/BEFORE_TAKE/APPLY_ATK/APPLY_DEF/AFTER_DEAL/AFTER_TAKE`
  - `DamageTrace.triggered_inst_ids` 为 `PackedInt32Array`（允许为空）
  - `DamageTrace.base_damage/final_damage/tags_mask/hit/crit` 字段存在且类型正确

该用例的目的不是重复验证伤害数值（已有 F2~F4 覆盖），而是锁死“阶段骨架 + 追帧契约”。

---

## 验收标准

- 新增 F1 专门用例通过
- 同步更新 checklist：F1~F5 标为完成

