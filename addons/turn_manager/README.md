# TurnManager Plugin for Godot 4.x

回合制战斗核心编排插件，负责驱动基于 `omnibuff` 和 `turn_skill_system` 的战斗流程。提供“每轮按速度重排”的行动队列与统一的状态机。

## 1. Unit Node 契约

`TurnManager` 直接使用你的单位节点。传入的单位必须具备以下字段：

### 必需字段
- `entity_id: int`
- `camp: String` (例如 `"ally"`, `"enemy"`)
- `cell: Vector2i`
- `stats` (OmniBuff.StatsComponent 实例)
- `buffs` (OmniBuff.BuffCore 实例)

### 推荐方法/字段
- `get_speed() -> float`: 提供当前速度，用于每轮开始时重排。
- `is_dead() -> bool` (或通过 `hp_stat_id` 自动推断死亡状态)。

## 2. BattleContext 构建模式

`BattleContext` 封装了战斗运行所需的所有核心依赖。

**模式 A: Autoload 优先（推荐）**
```gdscript
var ctx = BattleContext.new()
ctx.build_from_autoload() # 自动从 /root/TurnSkillRuntime 提取依赖
```

**模式 B: 手动注入**
```gdscript
var ctx = BattleContext.new()
ctx.grid = my_grid
ctx.event_bus = my_event_bus
ctx.dataset = my_dataset
# ... 手动赋值其余必需字段
```

## 3. 典型接入方式 (UI / AI)

```gdscript
var turn_manager = TurnManager.new()

# 1. 订阅信号
turn_manager.action_requested.connect(_on_action_requested)
turn_manager.battle_ended.connect(_on_battle_ended)

# 2. 启动战斗
turn_manager.setup(ctx, my_units)
turn_manager.start_battle()

func _on_action_requested(actor: Node, valid_skills: Array) -> void:
    # 显示 UI 或者 AI 决策
    var command = TurnCommand.new("skill_id", target_cell)
    turn_manager.submit_player_command(command)
```

## 4. 事件对齐

`TurnManager` 在关键阶段会自动通过 `BattleEventBus` 发出 `EventNames` 定义的事件：
- `TURN_STARTED`: 在应用 DOT 和 Buff 结算前发出。
- `ACTION_STARTED`: 提交 `TurnCommand` 后，执行技能前发出。
- `ACTION_FINISHED`: `SkillRuntime.cast_to_cell` 返回后发出。
- `TURN_ENDED`: 在回合结束 tick 结算后发出。
- `UNIT_DIED`: 每次清理死亡单位时对新死亡单位发出。

## 5. Demo 运行

可在 `addons/turn_manager/demo/demo_battle.tscn` 查看最小化调用流。
- 该场景自动挂载 `TurnManager`。
- 构建 2 个虚构单位。
- 在 `action_requested` 回调中模拟玩家或 AI 提交了一次 `TurnCommand`（`"strike"`）。
- 启动场景后查看控制台打印的事件序列。
