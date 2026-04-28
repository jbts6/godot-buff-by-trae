# OmniBuff Phase D 技术规范（P2/P3）

> 创建日期：2026-04-28
> 状态：已批准
> 版本：1.0

---

## 1. P2-1：Debug HUD 交互式增强

### 1.1 功能需求

| 需求ID | 描述 | 优先级 |
|--------|------|--------|
| HUD-01 | Stats Tab 中 base 值可通过 SpinBox 编辑，修改后实时触发脏标记重算 | 必须 |
| HUD-02 | Buffs Tab 中添加"Apply Buff"按钮（输入 buff_id）和"Remove"按钮（移除选中 buff） | 必须 |
| HUD-03 | 新增"Timeline"Tab，记录每次 emit_event 的调用（event_type, phase, 命中 inst_ids, 触发 actions） | 必须 |
| HUD-04 | 每回合 TurnStart/TurnEnd 保存 stats/buffs/dots 快照，支持"上一回合/下一回合"切换 | 可选 |

### 1.2 接口定义

```gdscript
# debug_hud.gd 新增方法
func apply_buff_by_id(buff_id_str: String, source_entity_id: int) -> void
func remove_buff_by_inst_id(inst_id: int) -> void
func set_stat_base(stat_name: String, value: float) -> void

# 事件时间线数据结构
class EventTrace:
    var turn: int
    var event_type: String
    var phase: String
    var hit_inst_ids: PackedInt32Array
    var action_summaries: Array[String]

# 回合快照数据结构
class TurnSnapshot:
    var turn: int
    var phase: String
    var stats_snapshot: Dictionary
    var buff_inst_ids: PackedInt32Array
    var dot_inst_ids: PackedInt32Array
```

### 1.3 数据结构

| 结构 | 用途 | 存储 |
|------|------|------|
| `_event_traces: Array` | 事件时间线记录 | 内存，最大 500 条 |
| `_turn_snapshots: Array` | 回合快照 | 内存，最大 20 回合 |
| `_timeline_box: RichTextLabel` | 时间线显示控件 | 场景节点 |

### 1.4 性能指标

- SpinBox 修改 base 值后，get_final() 重算延迟 < 1ms（单 stat）
- 事件时间线记录不影响伤害管线热路径（追加到 Array 的均摊 O(1)）
- 快照每回合内存增量 < 10KB（仅存 inst_id 列表 + stat base 值）

### 1.5 安全要求

- HUD 修改仅影响内存中的运行时状态，不写入任何文件
- Apply Buff 输入的 buff_id 必须在 CompiledDataset.buff_id_to_int 中存在，否则忽略
- SpinBox 输入值必须遵守 stat_def 的 min/max 约束

---

## 2. P2-2：跨平台确定性 RNG 保障

### 2.1 功能需求

| 需求ID | 描述 | 优先级 |
|--------|------|--------|
| RNG-01 | _roll01() 的浮点映射改为定点数运算，消除跨平台浮点差异 | 必须 |
| RNG-02 | 伤害公式中的浮点运算引入可选"定点模式" | 可选 |
| RNG-03 | 新增跨平台一致性测试 | 必须 |

### 2.2 接口定义

```gdscript
# damage_pipeline.gd 修改
static func _roll01(turn_index: int, roll_key: int, attacker_id: int, defender_id: int, salt: int) -> float:
    # 改为：先算 [0, 10000) 整数，再除以 10000.0
    var seed := _make_seed(turn_index, roll_key, attacker_id, defender_id, salt)
    var u := _xorshift32(seed)
    var fixed_point := u / 429497  # [0, 10000) 范围整数
    return float(fixed_point) / 10000.0

# DamagePipeline 新增配置
var use_fixed_point: bool = false  # 定点模式开关
```

### 2.3 数据结构

无新增数据结构，仅修改现有方法。

### 2.4 性能指标

- _roll01() 定点模式延迟增量 < 0.1μs（一次整数除法替代浮点除法）
- 伤害公式定点模式精度：3 位小数（千分位）

### 2.5 安全要求

- 定点模式为可选，默认关闭（向后兼容）
- 定点模式下的数值偏差不超过 0.001（千分之一）

---

## 3. P2-3：Scenario 数据驱动化

### 3.1 功能需求

| 需求ID | 描述 | 优先级 |
|--------|------|--------|
| SCN-01 | 定义 Scenario JSON schema | 必须 |
| SCN-02 | 实现 ScenarioRunner 类解析 JSON 并执行 | 必须 |
| SCN-03 | UI Demo 从 res://data/*/scenarios/ 自动扫描加载 | 必须 |
| SCN-04 | 保留 Callable 模式作为高级 scenario 后备 | 必须 |

### 3.2 接口定义

```gdscript
# scenario_runner.gd
class_name OmniScenarioRunner
extends RefCounted

func load_scenarios_from_dir(dir_path: String) -> Array[Dictionary]
func run_scenario(scenario: Dictionary, log_fn: Callable) -> bool

# Scenario JSON 格式
# {
#   "id": "test_atk_buff",
#   "title": "ATK Buff increases damage",
#   "dataset": "rpg_tests",
#   "setup": [
#     {"entity_id": 101, "base_stats": {"HP": 100, "ATK": 10, "DEF": 5}},
#     {"entity_id": 202, "base_stats": {"HP": 100, "ATK": 5, "DEF": 5}}
#   ],
#   "steps": [
#     {"action": "apply_buff", "entity_id": 101, "buff_id": "buff_atk_flat_20", "source_entity_id": 101},
#     {"action": "deal_damage", "attacker_id": 101, "defender_id": 202, "base_damage": 20.0},
#     {"action": "turn_end", "entity_ids": [101, 202]},
#     {"action": "turn_start", "entity_ids": [101, 202]}
#   ],
#   "assertions": [
#     {"path": "entity.202.stat.HP", "op": "lt", "value": 100},
#     {"path": "entity.202.stat.HP", "op": "gt", "value": 0}
#   ]
# }
```

### 3.3 数据结构

| 结构 | 用途 |
|------|------|
| Scenario JSON | 场景定义（setup + steps + assertions） |
| ScenarioRunner | 解析执行引擎 |
| `_json_scenarios: Array[Dictionary]` | UI Demo 中从文件加载的 scenario 列表 |

### 3.4 性能指标

- Scenario JSON 解析 < 10ms（单文件）
- 断言执行 < 1ms（单条）

### 3.5 安全要求

- Scenario JSON 中不允许执行任意代码
- 断言 path 仅允许 `entity.{eid}.stat.{name}` 和 `entity.{eid}.buff_count` 两种模式
- 文件路径必须在 res://data/ 下，不允许路径穿越

---

## 4. P2-4：策划配置指南

### 4.1 功能需求

| 需求ID | 描述 | 优先级 |
|--------|------|--------|
| DOC-01 | 配方索引："我想实现 XXX 效果，应该怎么配？" | 必须 |
| DOC-02 | 常见错误排查表 | 必须 |
| DOC-03 | 枚举值中文速查表 | 必须 |

### 4.2 交付物

文件路径：`addons/omnibuff/docs/designer_guide.md`

---

## 5. P3-1：BuffDef 子结构预编译为紧凑数组

### 5.1 功能需求

将 buff_defs 的 effects/triggers/dot 子结构从 Dictionary 编译为 PackedInt32Array + PackedFloat32Array 紧凑格式，运行时通过 int 索引 + 偏移量访问。

### 5.2 接口定义

```gdscript
# CompiledDataset 新增字段
var buff_effects_data: PackedInt32Array     # [stat_id, op_code, phase_code, layer, priority, ...]
var buff_effects_values: PackedFloat32Array # [value, ...]
var buff_effects_offsets: PackedInt32Array  # [start_idx, count] per buff_def
var buff_triggers_data: PackedInt32Array    # [event_type_code, phase_code, scope_code, action_kind_code, ...]
var buff_triggers_offsets: PackedInt32Array # [start_idx, count] per buff_def
```

### 5.3 性能指标

- Buff 施加时 effects 遍历性能提升 2-4x（数组索引 vs 字典查找）
- 编译期增量 < 5ms（100 个 buff_defs）

---

## 6. P3-2：StatsCore 派生属性计算优化

### 6.1 功能需求

mark_dirty() 时记录"脏源"stat_id 集合，recompute() 只重算脏源的依赖子集。

### 6.2 接口定义

```gdscript
# StatsCore 新增
var _dirty_sources: PackedInt32Array  # 脏源 stat_id 集合

func mark_dirty(stat_id: int) -> void:
    # 现有逻辑 + 追加 _dirty_sources
    if not _dirty_sources.has(stat_id):
        _dirty_sources.append(stat_id)

func get_final(stat_id: int) -> float:
    # 仅重算 _dirty_sources 的依赖子集
    if dirty[stat_id]:
        _recompute_dirty_chain()
```

### 6.3 性能指标

- 单 stat 变更时，避免重算无关派生属性
- 典型场景（1 个 stat 变化，10 个 stat 总量，3 个派生链）：重算量从 10 降至 3-4

---

## 7. P3-3：Mod 覆盖系统实现

### 7.1 功能需求

支持多数据集合并，按 mod_paths 顺序执行"last_wins_by_id"替换。

### 7.2 接口定义

```gdscript
# ManifestLoader 新增
static func load_dataset_with_mods(base_manifest_path: String, mod_paths: Array[String], strict: bool) -> Result
```

### 7.3 安全要求

- Mod 文件路径必须在 res:// 下
- 冲突日志不泄露文件系统绝对路径

---

## 8. P3-4：性能基准/压力测试 Scenario

### 8.1 功能需求

新增 benchmark_scenario，参数化实体数量/buff 数量/回合数，记录关键操作耗时。

### 8.2 接口定义

```gdscript
# benchmark_scenario.gd
func run_benchmark(entity_count: int, buff_count: int, turn_count: int) -> Dictionary
# 返回 {operation: String, avg_us: float, p99_us: float, total_us: float}
```

---

## 9. P3-5：OmniCsv 解析器增强

### 9.1 功能需求

| 需求ID | 描述 |
|--------|------|
| CSV-01 | 支持 RFC 4180 双引号包裹字段 |
| CSV-02 | 支持双引号转义（"" → "） |
| CSV-03 | split 保留空列（改为 allow_empty=true） |
| CSV-04 | 新增测试覆盖 |

---

## 10. P3-6：Bootstrap 与 Singleton 职责合并

### 10.1 功能需求

将 omnibuff_bootstrap.gd 的 preload 保障逻辑合并到 omnibuff_singleton.gd 的 _ready() 中，移除 bootstrap Autoload。

### 10.2 接口变更

- omnibuff_singleton.gd 的 _ready() 中新增 preload 所有脚本的逻辑
- omnibuff.gd（EditorPlugin）移除 bootstrap Autoload 注册
- 删除 omnibuff_bootstrap.gd

---

## 11. P3-7：Changelog 与迁移指南

### 11.1 交付物

- `addons/omnibuff/CHANGELOG.md`
- `addons/omnibuff/docs/migration/v1_to_v2.md`

---

## 12. P3-8：API 文档与代码对齐

### 12.1 功能需求

- 统一所有文档示例使用 deal_damage_v2
- 对"保留字段"标注实现状态
- 更新 api.md 中 DamagePipeline 的 v2 签名

---

## 13. P3-9：HUD 枚举反查优化

### 13.1 功能需求

在 EnumsRuntime 中新增 reverse_map，将 O(N) 反查优化为 O(1)。

### 13.2 接口定义

```gdscript
# EnumsRuntime 新增
var _reverse_tables: Dictionary  # enum_name -> {int_code: string_name}

func reverse_name(enum_name: String, code: int) -> String
```
