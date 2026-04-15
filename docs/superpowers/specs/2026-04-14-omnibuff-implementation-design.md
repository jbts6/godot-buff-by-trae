# OmniBuff（万物皆Buff）实现Spec（Godot 4.x）

日期：2026-04-14
目标工程根目录：`godot-buff/`
交付形态：**完整 Godot 工程 + addons 插件**

---

## 1. 目标与非目标

### 1.1 目标（必须满足）
- 回合制（TurnStart/TurnEnd 两阶段 tick），仅本地复盘（同版本同设备一致）。
- **性能硬规则**：
  - `deal_damage()` 过程中禁止遍历“攻击者全部Buff + 防守者全部Buff”。
  - 属性读取：只读 `StatCache.get_final()`。
  - 事件响应：只遍历 `EventIndex[event_type+phase]` 的监听子集（带 filters）。
- 数据源：CSV/JSON **唯一权威源**；以 `manifest.json` 为入口；base+mods 后加载覆盖前加载（last_wins_by_id），输出冲突报告。
- Schema治理：`schema_version`、兼容策略（strict/lenient）、错误定位（文件名+行号/JSONPath+ID）、迁移框架（在线/离线）。
- DOT：同种DOT **按来源独立实例**；每跳动态读取施法者当前状态（必须走StatCache）。

### 1.2 非目标（本轮不做或插件不包含）
- 不实现完整回合制战斗框架（行动队列/AI/UI流程等）。
- 不实现基于场景树的范围查询/光环影响（只提供接口，由项目方驱动）。
- 不生成任何派生缓存文件（.res/.bytes 等）。允许：启动时一次性解析并构建内存索引/紧凑结构。

---

## 2. 目录结构与交付内容

### 2.1 Godot 工程结构（最终）

```text
godot-buff/
  project.godot
  addons/
    omnibuff/
      plugin.cfg
      omnibuff.gd                  # EditorPlugin（可选：注册autoload/菜单）
      runtime/
        core/
          compiled_data.gd         # CompiledDataset（只读运行时数据）
          enums_runtime.gd         # enums.json编译结果（enum->int, tag->bit）
          expr_vm.gd               # 受限DSL（编译/执行）
          stats_core.gd            # StatCache + DirtyFlags + 重算
          buff_core.gd             # BuffInstance + Stack/Duration/Dispel + EventIndex
          event_index.gd
          damage_pipeline.gd       # 固定骨架（阶段/事件点）
          replay.gd                # 命令流 + trace/hash
        components/
          stats_component.gd
          buff_component.gd
          equipment_component.gd
          skill_component.gd
          turn_component.gd
      config/
        manifest_loader.gd
        parsers/
          csv_reader.gd
          json_reader.gd
        compiler/
          dataset_compiler.gd
          validators.gd
          migrate.gd               # 在线迁移框架
      demo/
        demo_scene.tscn            # 可运行最小demo
        demo_runner.gd
  data/
    base_demo/
      manifest.json
      enums.json
      stat_defs.json
      buff_defs.json
      equipment.csv
      set_bonus.json
      skill_defs.json
      damage_pipeline.json
    mods/
      mod_001/
        manifest_patch.json (可选)
        enums_patch.json    (仅允许tags新增)
        buff_defs.json
```

### 2.2 最小可运行 Demo（验收用）
Demo内容：
- 2个实体（attacker/defender）
- 1个武器（ATK+20）
- 1个被动（ATK+5%）
- 1个技能（造成伤害 + 自身3回合ATK+10 + 命中30%附加灼烧DOT）
- 1个套装4件（ATK+5%，条件失效采用 SUSPENDED 策略）
- 1个食物（5回合ATK+20）
- DOT（3回合/回合结束结算/按来源独立实例/每跳读取来源ATK快照）

---

## 3. 运行时核心边界（模块职责与依赖方向）

### 3.1 CompiledDataset（只读）
- 输入：Raw defs（来自CSV/JSON） + enums.json（权威枚举/Tag表）
- 输出：运行时只读结构（Packed数组、int索引、bitmask）
- 运行时核心只依赖 CompiledDataset，不依赖原始字段名

### 3.2 StatsCore（热路径只读）
职责：
- base_values / final_values / dirty_flags
- `get_final(stat_id)`：按需重算、返回快照
- 重算时只遍历该 stat 的**聚合 modifier 列表**（由 BuffCore 维护/更新）

### 3.3 BuffCore
职责：
- BuffInstance 生命周期：apply/stack/refresh/suspend/expire/dispel
- Stat影响：维护每个 stat 的 modifier 聚合视图；变化时 `mark_dirty_mask`
- 事件影响：维护 EventIndex；实例变化时 register/unregister listeners
- Tick：TurnStart/TurnEnd 两阶段；执行DOT/扣减/到期/条件变化（顺序固定）

### 3.4 DamagePipeline（固定骨架）
职责：
- 固定阶段顺序与事件点（BUILD/BEFORE_DEAL/BEFORE_TAKE/RESOLVE/APPLY/AFTER.../DEATH）
- 只通过 StatsCore 读取属性
- 只通过 BuffCore.emit_event 触发事件（EventIndex）
- 伤害公式可注入（策略接口）

### 3.5 Replay/Trace
职责：
- 记录命令流（cast skill/use item/equip change/target selection/rng）
- turn_hash（可选）用于一致性测试
- DamageTrace：记录 DamageContext 输入/输出 + 触发 inst_id 列表 + DOT来源快照

依赖方向（必须避免循环）：
`TurnComponent -> (BuffComponent, Replay)`
`SkillComponent -> (DamagePipeline, BuffComponent, Replay)`
`EquipmentComponent -> BuffComponent`
`DamagePipeline -> (StatsComponent, BuffComponent, Replay)`
`UI -> (Stats/Buff 查询只读)`

---

## 4. 数据加载、覆盖与fingerprint

### 4.1 加载顺序（固定）
1. `enums.json`（required=true，失败阻断）
2. stat_defs / buff_defs / equipment / set_bonus / skill_defs / damage_pipeline

### 4.2 base + mods 覆盖策略
- 策略：`last_wins_by_id`
- 输出冲突报告：哪个包覆盖了哪个ID（包含字段差异摘要可选）

### 4.3 fingerprint
- include：manifest自身 + manifest列出的所有文件
- method：content_hash（建议）
- replay一致性测试：同 fingerprint + 同命令流 → 输出hash一致

---

## 5. 里程碑（M0~M9）与每步验收点

### M0：工程与插件骨架
- 交付：Godot工程可打开；demo scene 可运行（暂时无战斗）。
- 验收：运行无报错；插件可启用/禁用。

### M1：数据加载闭环
- 交付：manifest/enums/defs 能加载并编译为 CompiledDataset；输出冲突报告；strict/lenient开关。
- 验收：加载 base_demo 成功；刻意造错（非法枚举/缺引用）能定位到文件+行号/JSONPath。

### M2：StatsCore（StatCache + DirtyFlags）
- 交付：stat_id映射；base/final/dirty；按需重算；apply_phase+priority生效。
- 验收：多次读取同stat不重复重算；修改base触发dirty并重算。

### M3：BuffCore（modifier-only）
- 交付：apply/remove/stack/refresh/duration；影响Stat的modifier聚合；标脏策略。
- 验收：apply一个ATK+20 buff 后，读取ATK发生dirty->重算；不遍历全buff。

### M4：DamagePipeline骨架（无事件反应器）
- 交付：按固定阶段跑通一次伤害；读取ATK/DEF等只走get_final；扣HP/护盾。
- 验收：deal_damage在日志中输出阶段顺序；性能规则仍成立。

### M5：EventIndex + Triggers + Filters
- 交付：实例变化时注册/注销监听；emit_event只遍历listeners[key]；filters生效；校验无filter告警。
- 验收：构造大量无关buff时，伤害事件遍历数量保持小；触发列表可追帧。

### M6：DOT（按来源独立）
- 交付：DotInstance池；TurnEnd tick；每跳读取来源ATK的StatCache快照；UI聚合key输出。
- 验收：两名施法者对同目标上灼烧：存在2个dot实例；每跳伤害随来源ATK变化而变化。

### M7：驱散语义
- 交付：按Tag/来源/类型驱散；不可驱散/免疫；输出驱散结果日志。
- 验收：驱散不会误删隐式buff（除非scope允许）；不可驱散正确生效。

### M8：本地回放/追帧
- 交付：命令流记录与重放；稳定顺序；DamageTrace与turn_hash（可选）。
- 验收：同fingerprint+同命令流重放输出一致；trace包含inst_id列表。

### M9：校验/迁移完善
- 交付：>=12条校验规则；migrate框架；离线迁移工具（可后置）。
- 验收：版本升级时在线迁移可运行；strict CI可阻断不合规mod。

---

## 6. 开发约束（实现时必须遵守）
- 任何热路径（damage/tick）不得线性扫描全buff列表。
- 任何公式读取属性必须通过 `StatsComponent.get_final(stat_id)`。
- 事件响应必须通过 `EventIndex`，并要求 triggers 至少提供一种filter（或在校验阶段报警）。
- 迭代顺序必须稳定（entity_id、inst_id、listener_id），回放模式下不得因swap-remove改变语义顺序。

---

## 7. 当前决策确认（已确认）
- Godot版本：**4.x**
- 交付形态：**完整Godot工程 + addons**
- 代码根目录：`godot-buff/`
