# turn_skill_system — 实施计划（plan）

> 前置：已完成 `turn_skill_system_spec.md`。本计划按“可运行最小闭环优先”拆解，确保每一步都能在 Godot 4.7 中验证。

---

## 0. 交付物清单（最终应落地到项目中）

> 你在需求里列出的“必须交付文件/目录”将在 Phase 1~6 逐步完成。

- `addons/turn_skill_system/plugin.cfg`
- `addons/turn_skill_system/plugin.gd`（EditorPlugin + Dock）
- `addons/turn_skill_system/editor/skill_editor_dock.tscn`
- `addons/turn_skill_system/editor/skill_editor_dock.gd`
- `addons/turn_skill_system/runtime/`
  - `skill_db.gd`
  - `skill_runtime.gd`
  - `battle_event_bus.gd`
  - `grid.gd`
  - `formula.gd`
  - `omni_buff_adapter.gd`
  - `targeting/*.gd`
  - （可选增强）`effects/*.gd` / `validators/*.gd` / `json_io.gd`
- `addons/turn_skill_system/data/skills/...`
  - 示例技能 JSON（3 个）
  - `index.json`
- `addons/turn_skill_system/demo/`
  - `demo_battle.tscn` + 对应脚本（snake_case）

---

## 1. Phase 0 — 决策确认（阻塞点，避免返工）

### 需要你确认的口径（建议一次性确认）
✅ 已确认：
1) `SkillRuntime`：允许插件启用时安装 Autoload（启用装/禁用卸载）
2) `damage` effect：必须走 `OmniBuff.DamagePipeline`（优先 `deal_damage`，必要时兜底 `deal_damage_v1`）
3) 公式默认取整策略：`floor`

仍需你确认：
✅ 已确认：
1) `Unit` 接入：字段契约（entity_id/camp/cell/stats/buffs）

仍需你确认：
1) 事件命名是否需要对齐你现有战斗事件命名（若有）

> 若你只回一句“按 spec 推荐选项走”，即可进入 Phase 1。

---

## 2. Phase 1 — 插件骨架 + 最小运行时（不做编辑器）

**目标**：先让 `SkillDB + SkillRuntime` 在纯脚本里跑通，保证 cast/simulate 的数据结构稳定。

### 任务
1. 创建目录与 plugin.cfg/plugin.gd（可先不注册 Dock）
   - 同时实现：启用插件时安装 Autoload（禁用时卸载）
2. 实现 `runtime/skill_db.gd`
   - index 读取
   - `get_skill(id)` lazy load + cache
   - reload/refresh
3. 实现 `runtime/formula.gd`
   - Expression 封装
   - a/t 变量映射
   - rounding
   - resolved_formulas 结构
4. 实现 `runtime/grid.gd`
   - 3×3
   - camp/unit 管理 + 查询
5. 实现 `runtime/targeting/`（最少 3 个规则）
   - single_cell
   - all_enemies / all_allies（二选一也可，另一个用 params 实现）
   - row 或 cross（至少一个形状）
6. 实现 `runtime/battle_event_bus.gd`
   - `emit(type, data)`
   - signals + 事件记录（用于 cast 返回 events）
7. 实现 `runtime/skill_runtime.gd`
   - cast/cast_to_unit/cast_to_cell/simulate_cast
   - 先实现 effect：damage/heal 的结构与返回值（damage 仍走 omnibuff pipeline；若还未完成 adapter，可先 stub 但保持接口不变）
   - active 兼容 `rpg_tests/skill_defs.json`：支持 `hit_count/hit_base_damage/on_cast/on_hit/targeting(字符串)` 的解析与执行顺序

### 验证点
- 能在一个最小脚本（或临时场景）里：
  - 加载 index.json
  - simulate_cast 返回结构满足约定

---

## 3. Phase 2 — omnibuff 适配层 + Buff/伤害联动

**目标**：把 Buff 操作与伤害结算接到 omnibuff，满足“不要重复造 buff 轮子”。

### 任务
1. 实现 `runtime/omni_buff_adapter.gd`
   - `apply_buff(target_unit, buff_id, source_unit, ctx)`
   - `remove_buff(...)`
   - `simulate_apply_buff(...)` / `simulate_remove_buff(...)`
   - `deal_damage(...)`：内部优先调用 `OmniBuff.DamagePipeline.deal_damage(...)`；必要时兜底到 `deal_damage_v1(...)`
2. 扩展 `damage` effect：
   - base_damage 来自 formula
   - 调用 adapter.deal_damage 得到 final_damage（并从 attacker/defender stats 中读取 HP 变化用于回放数据）
3. 与 omnibuff 的 runtime dict 对齐：
   - demo/运行时维护 `runtime = {"stats_by_entity":...,"buff_by_entity":...}`

### 验证点
- Demo 能成功：
  - 对目标 apply_buff（BuffCore.apply_buff）
  - remove_buff（remove_by_buff_id）
  - damage 结算后 HP 变化符合预期（且 Buff 能影响伤害/触发 omnibuff 事件：若数据集配置了 DAMAGE 事件动作）

---

## 4. Phase 3 — 被动技能（Passive）与触发系统

**目标**：具备基础触发闭环：事件发生 → passive evaluate → effects 执行。

### 任务
1. 定义 `BattleEventBus` 的事件常量集合（集中在一个文件）
2. 实现 `PassiveManager`（可作为 `SkillRuntime` 内部模块或独立脚本）
   - 注册：`register_passives(unit, skill_ids)`（或从 unit 的装备/职业系统注入）
   - 监听 event_bus 事件，按 triggers 执行
3. 实现最小 `conditions`（至少 2 个）
   - `always`
   - `chance_roll`（支持 deterministic：用 rng_seed + roll_key）

### 验证点
- 在 demo 中：
  - turn_started 事件触发一个被动给自己上 buff（apply_buff）

---

## 5. Phase 4 — 光环（Aura）系统（进入/离开动态应用/移除）

**目标**：实现 AuraManager：范围变化时动态生效/移除，且可模拟。

### 任务
1. `AuraManager`（独立脚本或集成在 SkillRuntime）
   - `register_aura(owner_unit, aura_skill_id)`
   - 跟踪 `affected_set`（owner_id -> Set[target_id]）
2. 监听以下事件（来自 event_bus 或 grid 回调）：
   - `unit_moved` / `grid_changed` / `unit_died`
3. 触发差集：
   - enter -> on_enter effects
   - exit  -> on_exit effects
4. simulate 模式：
   - 不实际 apply/remove buff，只输出 predicted_deltas

### 验证点
- demo：
  - 一个 ally 光环覆盖前排：前排单位进入/离开时 buff 正确增减

---

## 6. Phase 5 — JSON 校验、稳定写回、index 生成器

**目标**：满足“开放 JSON、unknown fields 保留、错误定位、index 性能”。

### 任务
1. `skill_validator.gd`
   - strict/lenient
   - file_path + field_path
   - 兼容层：
     - 当 `targeting` 为字符串（FIRST/ALL）时，自动归一化为内部结构并给出 warning（编辑器可一键迁移）
     - 当 active 存在 legacy 字段 `effects` 时，提示并支持一键迁移到 `on_cast`
2. `json_io.gd`
   - stable order + stable indent
   - unknown fields merge 写回
3. `index_builder.gd`
   - 扫描三目录，输出 index.json
   - mtime_unix

### 验证点
- 手改 JSON 增加额外字段后，编辑器保存不丢字段
- index 生成稳定可重复（git diff 尽量少变）

---

## 7. Phase 6 — Editor Dock（浏览/搜索/新建/编辑/预览）

**目标**：在 Godot 编辑器里完成你列出的 Dock 功能闭环。

### 任务
1. `editor/skill_editor_dock.tscn` + `.gd`
   - 左：列表 + 过滤
   - 右：编辑区（基础字段 + targeting + effects + triggers/aura）
   - 底：日志/预览输出
2. 新建技能：
   - 生成模板（按 type）
   - 自动写入对应目录
3. 预览/测试：
   - 调用 `SkillRuntime.simulate_cast`
4. 一键更新 index.json

### 验证点
- 编辑器内从 0 创建一个 skill → 保存 → 生成 index → simulate 成功

---

## 8. Phase 7 — Demo 场景与 README（交付闭环）

**目标**：用户拉下仓库即可启用插件并运行 demo，验证三类技能都能跑。

### 任务
1. `demo/demo_battle.tscn` + 脚本
   - 生成 2~4 个 demo_unit
   - 初始化 omnibuff dataset + runtime dict
   - 挂载 event_bus / runtime
2. 写入 3 个示例技能 JSON + index.json
3. `addons/turn_skill_system/README.md`
   - 启用方式
   - JSON 技能创建/编辑/index 生成
   - cast/cast_to_unit/cast_to_cell 使用方式
   - simulate_cast 用于 AI 评估
   - 扩展点
   - omnibuff 对接点（集中在 omni_buff_adapter.gd）

---

## 9. 风险与回滚策略

### 风险 1：omnibuff 数据集/ID 不匹配导致 demo buff_id 不存在
- 规避：demo 读取 `base_demo`，并选用其中明确存在的 buff_id；或在 README 标注需替换 buff_id。

### 风险 2：Expression 安全/可维护性
- 规避：只暴露纯数据 dict，不暴露对象；错误信息写入 `resolved_formulas` 与 `errors`。

### 风险 3：unknown fields 在数组元素中丢失
- 规避：effects/triggers 建议支持可选 `uid`；无 uid 时按 index 合并保留。

---

## 10. 完成定义（Definition of Done）

1. 插件可启用/禁用，不报错；
2. Dock 面板可新建/编辑/保存 JSON，且 unknown fields 不丢；
3. index.json 支持 lazy load + cache；
4. cast/simulate_cast 返回结构符合约定；
5. Demo 场景可运行，展示：
   - 单体主动伤害（公式）
   - AoE 主动伤害（形状）
   - passive 或 aura 通过 omnibuff 上/下 buff（动态进入离开）
