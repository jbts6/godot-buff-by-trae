# 整回合脚本式集成测试设计（OmniBuff + GUT）

## 目标

新增一组“更像真实战斗”的**整回合脚本式** GUT 集成测试，用可读的脚本流程覆盖关键交互：

1. 护盾（SHIELD）吸收
2. 三连击（多段攻击）
3. 每段攻击 AFTER_DEAL 施加 DOT
4. DOT 结算在“目标回合开始”（TurnStart）
5. 驱散（按 tag=DEBUFF）
6. 驱散免疫（对 DEBUFF 免疫，驱散失败）

该测试应具有：
- **可读性**：像战斗脚本一样分回合执行
- **可回归**：断言 HP/SHIELD/DOT trace/驱散结果
- **不污染 demo 数据**：继续使用 `data/rpg_tests` 数据集（必要时仅补最小数据项）

---

## 测试入口与文件

新增测试文件：
- `res://addons/omnibuff/tests/rpg/test_full_turn_script_battle.gd`

测试数据：
- 复用 `res://data/rpg_tests/*`
- 若需要额外 buff（例如“驱散免疫 DEBUFF”），优先新增到 `data/rpg_tests/buff_defs.json`，并以 `buff_test_*` 命名。

---

## 场景脚本（回合流程）

参与实体：
- attacker（攻击方，entity_id=9001）
- defender（防守方，entity_id=9002）

基础约定：
- 每回合以 `turn_index` 驱动确定性 RNG（命中/暴击）。
- 测试中为保证稳定性，默认使用：
  - attacker：`HIT_RATE=1`（确保命中）；
  - attacker：`CRIT_RATE=0`（避免偶发暴击干扰数值断言）。
  - 若要验证暴击，可另写独立用例（已有 `test_hit_and_crit_deterministic.gd`）。

### Turn 1：防守方上盾
动作：
- defender 施加 `buff_shield_50`

断言：
- defender.SHIELD == 50
- defender.HP == 100

### Turn 2：三连击（每段 AFTER_DEAL 施加 DOT）
动作：
- attacker 施加 `buff_on_hit_apply_dot`（DAMAGE/AFTER_DEAL -> APPLY_BUFF -> buff_dot_fire_3t）
- 对 defender 连续 3 段攻击：base_damage = [12, 14, 18]

断言：
- 三连结束后：defender 身上 DOT 实例数 == 3（都为 buff_dot_fire_3t）
- Turn 3 Start：结算 DOT（应结算 3 个 DOT 实例）
- Turn 3 Start 后：新增 DotTrace 条数 == 3；每条 source_entity_id == attacker_id
- SHIELD/HP 数值：护盾先吸收，再扣血（按当前 DamagePipeline 逻辑）

### Turn 3：驱散（按 tag=DEBUFF）
动作：
- 对 defender 执行 `dispel_by_tag("DEBUFF", false)`
- Turn 4 Start：再次结算 DOT（预期不会再产生 trace）

断言：
- removed > 0（至少移除 DOT）
- defender 的 DOT 池为空（或 TurnEnd 不产生新的 DotTrace）

### Turn 4：免疫驱散（对 DEBUFF 免疫）
动作：
- 再次通过三连击给 defender 挂 3 个 DOT（同 Turn2；DOT 将在 Turn 5 Start 结算）
- 给 defender 设置“驱散免疫 DEBUFF”
  - 方案：直接设置 `defender_buff.target_dispel_immunity_mask |= tag_mask(["DEBUFF"])`
  - 或新增 `buff_dispel_immune_debuff`（若希望完全数据驱动）
- 执行驱散：`dispel_by_tag("DEBUFF", false)`（预期失败）
- Turn 5 Start：DOT 仍应结算（产生 trace）

断言：
- removed == 0
- Turn 5 Start 新增 DotTrace 条数 == 3

---

## 实现策略（可读性优先）

在测试脚本中构建“战斗脚本”辅助函数：

- `func _make_battle()`：构造 ds/enums_rt/pipe/replay + attacker/defender + runtime dict
- `func _deal_multi_hit(base_hits, turn_index)`：循环调用 `pipe.deal_damage(...)`
- `func _turn_end(turn_index)`：调用 `turn.on_turn_end(...)`，并返回新增 DotTrace 数量
- `func _assert_dot_trace_added(before_idx, expected_count, expected_source_id)`：统一断言 trace

这样测试主体会更像：
- Turn1：apply buff → assert
- Turn2：apply trigger buff → multi-hit → turn_end → assert
- Turn3：dispel → turn_end → assert
- Turn4：multi-hit → set immunity → dispel → turn_end → assert

---

## 验收标准

- GUT 中该测试脚本 PASS
- 断言覆盖：护盾消耗顺序、DOT 实例数量、DOT trace 数量、驱散成功/失败、免疫语义
- 测试输出不依赖肉眼观察（所有关键点都有 assert）
