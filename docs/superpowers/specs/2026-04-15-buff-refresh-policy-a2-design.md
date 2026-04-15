# OmniBuff A2（刷新策略）设计：refresh_policy=RESET_TO_MAX

## 目标

在已完成 A1（叠加策略）与 A3（非 DOT 到期）基础上，补齐 A2：**刷新策略**。

本阶段范围（按确认）：
- 实现 `stack.refresh_policy = "RESET_TO_MAX"` 的语义，并让该语义**可配置**（不再是硬编码“命中就刷新”）。

## 现状与问题

当前 `BuffCore.apply_buff` 的 `ADD_STACK` 命中已有实例时，会无条件：
- `remaining_turns = turns`（重置到满值）

这等价于把 `RESET_TO_MAX` 写死在代码里：
- 无法表达“不刷新”（NONE）
- 无法扩展其它策略（EXTEND/RESET_ONLY_IF_LOWER）
- 测试层面也无法锁死策略矩阵

## 数据协议（已有字段）

buff_def.stack 中：

```json
"stack": {
  "mode": "ADD_STACK",
  "max_stack": 3,
  "refresh_policy": "RESET_TO_MAX",
  "ownership_mode": "GLOBAL"
}
```

## 行为定义（本阶段落地）

### 1) 适用范围

刷新策略仅对“命中已有归属实例”的情况有效：
- `stack.mode == "ADD_STACK"`：命中已有实例时可刷新
- `stack.mode == "REPLACE"`：本质是移除旧实例并创建新实例，新实例本来就是满回合，不需要 refresh_policy
- `stack.mode == "MULTI_INSTANCE"`：每次新建实例，天然是满回合，不需要 refresh_policy

### 2) RESET_TO_MAX 语义

当 `stack.mode == "ADD_STACK"` 且命中已有实例时：
- 若 `refresh_policy == "RESET_TO_MAX"`：`remaining_turns = duration.turns`

### 3) 默认值与兼容策略

为了兼容旧数据（以及当前大多数 RPG 预期），本阶段约定：
- 若 `refresh_policy` 缺失或为空字符串：视为 `"RESET_TO_MAX"`
- 若 `refresh_policy` 为其它值（例如未来的 `"NONE"`）：本阶段先按“不刷新”处理（即保持 remaining_turns 不变）

> 这使得我们能够在不实现完整矩阵的前提下，把“硬编码刷新”改造成“可配置刷新”，并为后续扩展留出空间。

## 测试策略（GUT）

新增测试用例验证：
1) `refresh_policy` 缺失时默认为 RESET_TO_MAX（兼容）
2) `refresh_policy="RESET_TO_MAX"` 时，ADD_STACK 命中已有实例会刷新 remaining_turns（锁死核心语义）
3) （可选但建议）增加一个 `refresh_policy="NONE"` 的测试 buff，验证“不会刷新”，以证明策略是可配置的

## 非目标

本阶段不实现（仅保留兼容处理）：
- `NONE`
- `EXTEND`
- `RESET_ONLY_IF_LOWER`

## 验收标准

- `BuffCore.apply_buff` 的刷新行为由 `stack.refresh_policy` 驱动（不再硬编码）
- 新增的 A2 测试用例全绿
- 现有测试（A1/A3、伤害、DOT、驱散等）不回归

