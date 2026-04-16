# OmniBuff：对标 MOBA 的路线图（按收益/风险/侵入度排序）

> 目标标杆：LOL / Dota 级别的线上对战 Buff 系统。
>
> 排序原则：**先做高收益、低风险、低侵入度**的能力（更像“产品化/工具化/玩法覆盖”），再进入数值体系深水区与网络/回滚等高成本方向。

---

## 总览（阶段划分）

### Phase 0：工具化 + 可观测性（低风险 / 低侵入）
让“为什么生效/为什么不生效”从读代码变成看 HUD/日志，打造可交付的 Demo/QA 工作流。

### Phase 1：事件域 + 选择器/动作扩展（低~中风险 / 低~中侵入）
补齐 MOBA 常用的触发条件与动作集合，让策划能用 data 驱动组合出 60% 常见效果。

### Phase 2：数值表达能力升级（中风险 / 中侵入）
把成长、装备、属性派生、桶/phase 等“数值系统根基”做成工业级，保证可复刻并可维护。

### Phase 3：技能实例化 + 网络/回放升级（高风险 / 高侵入）
支持并发技能实例、投射物、多段延迟、服务器权威、预测回滚、观战/复盘等对战级需求。

---

## Phase 0（低风险 / 低侵入）：工具化 + 可观测性

### 0.1 Debug HUD（核心）
- **Stats**：常用 stat 的 final/base/dirty
- **StatMods**：按 stat 分组列出 modifiers（op/phase/value/layer/priority/source_inst_id，并反查 buff_id）
- **Buffs**：buff 实例列表（明确 DOT turns 不在 BuffInst 上）
- **Dots**：DotInstance 权威 turns/stacks（来源/聚合/owner_inst）
- **Listeners**：按 event_type/event_phase 分组，展示 filters/action 摘要 + last_triggered_inst_ids
- **Copy dump**：结构化分区、长度上限、便于贴 issue

### 0.2 UI Demo（Scenario Runner）
- dataset 切换（base_demo/rpg_tests）
- scenario 列表、run selected/run all、日志输出与复制
- 将 `tests/rpg` 的能力点转为可交互场景（便于 QA/设计复现）

### 0.3 Validate/Lint（协议治理）
- action.kind 字段要求矩阵（例如 APPLY_BUFF 的 buff_id/add_stacks；SET_STAT_FINAL 的 stat/value；DOT_* 的 dot_buff_id/tag_mask_any）
- 针对高风险配置给 lint warning（监听过宽、缺 require_hit 等）

**产出标准：**
> 任何一个问题都能通过：复现 scenario → HUD 观察 → 复制日志+dump → 不跑游戏也能定位 80% 根因。

---

## Phase 1（低~中风险 / 低~中侵入）：事件域 + 选择器/动作扩展

### 1.1 Filter/Selector 扩展（让“条件”更像 MOBA）
优先级（从常用到进阶）：
- skill_id、damage_type/element、tags_mask_any（已部分有）
- 阵营/单位类型（英雄/小兵/野怪等）
- 距离、是否暴击、是否被护盾吸收、是否普攻/技能
- require_hit（已支持）
- stat_threshold（已支持最小版）

### 1.2 Action 扩展（仍保持白名单 DSL）
优先补 MOBA 高频动作：
- HEAL / LIFESTEAL / REFLECT_DAMAGE
- ADD_SHIELD（护盾作为资源而不是纯 modifier）
- DISPEL（作为 action，技能触发驱散）
- APPLY_BUFF：支持 add_stacks（已支持）
- stack 精细控制：APPLY_BUFF_STACK / REMOVE_STACK（或扩展现有 APPLY_BUFF）
- 资源类：MANA/ENERGY 等（按你们项目需要）

### 1.3 事件域扩展（触发时机更全面）
- 施法开始/结束、投射物命中、移动、死亡/复活、击杀/助攻、购买/获得装备等（按项目需要选取）

**产出标准：**
> 设计能用数据拼出：加速/减速、沉默/缴械、持续伤害/吸血、反伤、触发型被动等常见技能机制，而不是靠新增硬编码。

---

## Phase 2（中风险 / 中侵入）：数值表达能力升级

### 2.1 派生/转换属性（Derived/Convert）
例如 STR→HP、INT→AP、AP→技能伤害倍率等。
- 需要依赖图、拓扑排序、循环依赖检测、dirty 传播

### 2.2 更精细的 phase 与“桶”规则
base / bonus / total / final / post-final；不同系统的乘法隔离（你们已有 percent layers 的雏形）。

### 2.3 非线性与曲线
等级缩放、递减收益（DR）、软上限、指数/对数曲线等。

**产出标准：**
> 可以稳定复刻“加成先后顺序”和“不同来源乘法隔离”，数值不再靠试出来。

---

## Phase 3（高风险 / 高侵入）：技能实例化 + 网络/回放升级

### 3.1 技能实例上下文（Skill Instance Context）
每次施法拥有 instance_id：多段/投射物/延迟触发都绑定该上下文，避免串线。

### 3.2 网络模型
服务器权威、客户端预测、回滚重放、状态快照压缩、断线重连。

### 3.3 更严格的确定性
随机源管理、排序稳定性、浮点一致性（必要时固定点）。

**产出标准：**
> 支持多人对战、观战、复盘、断线重连，并能在压力下保持同步一致。

---

## 推荐推进顺序（最划算）

1) **Phase 0** 做满（工具链与可观测性）→ 团队效率提升最大  
2) 进入 **Phase 1**（动作/过滤器/事件域）→ 玩法覆盖快速像 MOBA  
3) 再做 **Phase 2**（数值体系根基）→ 支撑装备/成长与长期维护  
4) 最后再考虑 **Phase 3**（对战网络与回滚）→ 成本最高、收益依赖产品形态

