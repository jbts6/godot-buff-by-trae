# OmniBuff Phase 2：数值表达能力升级（Derived/Convert + Buckets + Curves）设计

## 背景（对齐 roadmap）

Roadmap Phase 2 目标是把“成长、装备、属性派生、桶/phase、曲线”等数值根基做成可维护、可复刻的工业级实现，避免数值顺序靠试出来。

当前实现（`OmniStatsCore`）已经具备雏形：
- 支持 `ADD/FLAT`、`MUL/PERCENT`（含 percent layer）、`ADD/FINAL`、`OVERRIDE/FINAL`、clamp
- 但缺少：派生/转换属性、明确的 bucket/phase 规则、曲线/DR 等非线性表达、以及依赖图/dirty 传播

本 Phase 2 设计在保持现有行为可复刻的前提下，向“可扩展的数值 pipeline”演进。

---

## 目标

1) **派生/转换属性**（Derived/Convert）
- 用数据表达诸如 `STR → HP`、`AP → SkillScale` 的线性转换与表达式派生
- 具备依赖图、拓扑排序、循环依赖检测
- 具备 dirty 传播：当来源 stat 变化时，自动标记受影响的派生 stat

2) **更精细的 phase/bucket 规则**
- 明确计算流水线：`BASE → FLAT → PERCENT(layers) → OVERRIDE → FINAL_ADD → POST_FINAL → CLAMP`
- 不同来源的乘法隔离通过 `PERCENT layer`（延续现有雏形），并约定 layer 的排序与可读性

3) **非线性/曲线（Curves）**
- 提供“声明式曲线”能力：等级缩放、递减收益（DR/Softcap）、指数/对数等
- 保证确定性（同输入同输出），并可在派生/或最终阶段使用

4) **兼容性**
- 不破坏现有 `stat_defs.json`、buff modifiers、tests 的语义
- 新能力均为可选字段；不使用时行为与当前一致

5) **属性面板所需的“分段值”读取**
- 读取单个 stat 时，能同时拿到：
  - `base`（含派生/转换叠加后的 base）
  - `bonus`（来自 buff/modifiers/曲线等带来的增量）
  - `final`
- 用于 UI 直观展示（例如 HP：基础值、加成值、最终值）

---

## 非目标

- Phase 3 的网络/回滚/固定点数值一致性
- 大规模性能极限优化（Phase 2 先把结构做对；性能瓶颈再进行紧凑化）

---

## 配置协议（stat_defs.json 扩展）

> 本轮按你的选择：**扩展 `stat_defs.json`**，不新增单独 derived_defs 文件。

### 1) 派生/转换（derived）

在 stat 定义中新增可选字段 `derived`：

#### 1.1 线性转换（LINEAR）

```jsonc
{
  "id": "HP",
  "default": 100,
  "clamp": true,
  "min": 0,
  "max": 99999,
  "derived": {
    "type": "LINEAR",
    "from": "STR",
    "ratio": 20.0,
    "round": "NONE"          // NONE|FLOOR|ROUND|CEIL（可选，默认 NONE）
  }
}
```

语义：`HP.base += STR.final * ratio`（注意是“对 base 的派生加成”，不是直接覆盖 HP）。

#### 1.2 表达式派生（EXPR）

```jsonc
{
  "id": "AP",
  "default": 0,
  "derived": {
    "type": "EXPR",
    "expr": "INT * 3 + LVL * 1.5",
    "inputs": ["INT", "LVL"],
    "round": "FLOOR"
  }
}
```

语义：`AP.base += eval(expr, inputs=deps.final)`。

约束：
- `inputs[]` 必须显式列出（便于编译期建图与循环检测）
- `expr` 长度限制（例如 <=256）与可用变量名集合，由 validators 治理

### 2) 曲线（curve）

在 stat 定义中新增可选字段 `curve`，表示 **在某个阶段对该 stat 应用曲线变换**。

```jsonc
{
  "id": "DMG_REDUCE",
  "default": 0.0,
  "clamp": true,
  "min": 0.0,
  "max": 0.95,
  "curve": {
    "type": "DR_SOFTCAP",
    "k": 100.0,
    "apply_at": "POST_FINAL"
  }
}
```

建议支持的 `curve.type`（Phase 2 最小集）：
- `NONE`（缺省）
- `DR_SOFTCAP`：`f(x)=x/(x+k)`（递减收益）
- `EXP`：`f(x)=a*exp(b*x)+c`
- `LOG`：`f(x)=a*log(b*x+c)+d`

`apply_at`：
- `POST_FINAL`（默认）：在 `OVERRIDE + FINAL_ADD` 之后、clamp 之前应用

---

## 编译期（DatasetCompiler）产物（OmniCompiledDataset 扩展）

为避免运行时反复解析 JSON，本轮在 `OmniCompiledDataset` 增加“派生图”相关只读结构：

- `derived_defs_by_stat: Array[Dictionary]`（index=stat_id；无则空字典）
- `derived_inputs_by_stat: Array[PackedInt32Array]`（index=stat_id；依赖的 stat_id 列表）
- `derived_dependents_by_stat: Array[PackedInt32Array]`（反向边，用于 dirty 传播）
- `derived_topo_order: PackedInt32Array`（拓扑序；用于批量更新派生 base）

编译规则：
- 从 `stat_defs[i].derived.inputs` / `derived.from` 构造有向图
- 做拓扑排序 + 循环检测；若检测到循环，直接在 validate 阶段报错阻断

---

## 运行时（StatsCore）计算模型

### 1) 数据结构

在 `OmniStatsCore` 增加：
- `computed_base: PackedFloat32Array`（index=stat_id；派生/转换叠加到 base 的“额外 base”）

最终 base 计算：
- `base = base_values[stat_id] + computed_base[stat_id]`

### 2) 派生更新

当某个 stat 发生变动（base 改变 / modifiers 改变）：
- `mark_dirty(stat_id)` 仍然标记自身 dirty
- 同时通过 `derived_dependents_by_stat` 把所有“依赖该 stat 的派生 stat”也标记 dirty

在 `get_final(stat_id)` 触发重算前，需要确保该 stat 的 `computed_base` 已刷新：
- 按 `derived_topo_order` 计算受影响派生 stat 的 `computed_base`
- 对于 EXPR：`Expression` 采用“编译一次，多次执行”的策略（类似 BONUS_DAMAGE expr）

### 3) bucket/phase 顺序（对齐现有行为）

现有等价规则应保持：
- `(base + flat) * Π(1+pct[layer])`，layers 按 layer 升序
- `OVERRIDE/FINAL` 优先级：priority 高者胜，priority 相同取 source_inst_id 大者胜
- `final_add` 在 override 后追加
- clamp 最后执行

Phase 2 明确成管线（默认与现有一致）：
1. `BASE`：`base_values + computed_base`
2. `FLAT`：sum `ADD/FLAT`
3. `PERCENT`：按 layer 聚合并按 layer 升序依次乘
4. `OVERRIDE`：`OVERRIDE/FINAL`
5. `FINAL_ADD`：`ADD/FINAL`
6. `POST_FINAL`：保留扩展点（Phase 2 最小实现可先视作空）
7. `CURVE`：若配置 `curve.apply_at=POST_FINAL`，在此应用
8. `CLAMP`

---

## 属性面板：base/bonus/final 的定义与 API

### 定义（对 UI 友好）

对任意 stat：
- `base`：`base_values + computed_base`
  - `base_values`：角色基础（成长/装备基础等由上层系统写入）
  - `computed_base`：派生/转换叠加出的 base 增量（Phase 2 新增）
- `final`：完整 pipeline 结算后的最终值（含 flat/pct/override/final_add/curve/clamp）
- `bonus`：`final - base`

> 说明：如果某些 stat 使用 curve/DR，`bonus` 会包含“曲线变换”导致的差值（这是 UI 更直观的展示：最终比基础多/少了多少）。

### API（最小集）

在 `OmniStatsCore` 提供：
- `get_breakdown(stat_id) -> Dictionary`
  - 返回：`{"base": float, "bonus": float, "final": float}`
  - 并可选附带更细字段（便于 debug/HUD）：
    - `flat`、`pct_by_layer`、`override`、`final_add`、`curve_applied`、`clamped`

在 `OmniStatsComponent` 提供薄封装：
- `get_breakdown(stat_id) -> Dictionary`（直接转调 core）

## 协议治理（validators）

在 `addons/omnibuff/config/compiler/validators.gd`：
- `stat_defs` 允许新字段：`derived`、`curve`
- `derived.type` 白名单：`LINEAR/EXPR`
- `LINEAR` 必须包含 `from/ratio`
- `EXPR` 必须包含 `expr/inputs`，inputs 不能为空，且每个输入 stat id 存在
- `curve.type` 白名单，参数范围校验（例如 k>0）
- expr 字符串长度限制 + 非法字符拦截（最小：非空、<=256）

---

## 测试策略（Phase 2 验收）

新增 `tests/rpg/test_phase2_numerics_*.gd` 覆盖：
1) `STR → HP` 线性派生：修改 STR base 后，HP final 跟随变化（且 dirty 传播生效）
2) EXPR 派生：依赖两项 stat，验证结果与 round 规则
3) bucket 顺序：flat vs pct vs override 的先后不变（回归现有 percent layer 测试，并新增覆盖）
4) curve：DR_SOFTCAP 的单调性与边界（clamp 前后）

---

## 迁移 / 兼容策略

- 旧数据不含 `derived/curve`：不受影响
- 旧 modifier（add_value）兼容仍保留（Phase 2 不移除）
