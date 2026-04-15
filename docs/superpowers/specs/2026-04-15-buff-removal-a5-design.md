# OmniBuff A5（主动移除接口稳定）设计（第一档）

## 目标

把“主动移除”做成一个对调用者友好、语义稳定、可回归的 API 集合，并用 GUT 锁死以下不变量：

1. 移除后 **属性立即回退**（撤销 modifiers + mark_dirty）
2. 移除后 **事件不再触发**（listeners 注销）
3. 移除后 **DOT 不再 tick**（dots_by_target 清理或暂停）
4. 无论实例当前处于 **active/inactive**（A4）都能正确移除与清理

> 注意：我们已经有 `remove_by_instance()`、驱散（dispel_*）与 DOT 清理逻辑；A5 的重点是：补齐 “对外 API 面 + 系统性测试 + 边界语义”。

---

## 现状

已有（运行时）：
- `remove_by_instance(stats, inst_id, force=false)`：撤销 modifiers、注销 listeners、清理 DOT、从实例表删除
- `dispel_by_tag/source/type(...)`：驱散语义（含免疫、undispellable、include_implicit）

缺口（A5 第一档）：
- 没有“按 buff_id/tag/source/type”等 **更高层主动移除 API**（调用者需要自己遍历 inst_ids）
- 没有“移除后不再触发事件”的回归用例（例如 AFTER_DEAL 施加 DOT 的监听被移除）
- 没有明确的“主动移除 vs 驱散”的 API 分层与命名约定

---

## API 设计（第一档）

### 1) 保留现有底层 API（不变）

```gdscript
remove_by_instance(stats: OmniStatsComponent, inst_id: int, force: bool=false) -> bool
```

语义：删除一个具体实例（最底层）。

### 2) 新增主动移除 API（对调用者友好）

#### 2.1 按 buff_id 移除

```gdscript
remove_by_buff_id(stats, buff_id_str: String, scope := "ALL", source_entity_id := -1, include_implicit := false, force := false) -> int
```

- `scope`：
  - `"FIRST"`：移除一个（按 inst_id 升序的第一个）
  - `"ALL"`：移除所有匹配的实例（默认）
- `source_entity_id`：
  - `-1` 表示不按来源过滤
  - 否则只移除 `inst.source_entity_id == source_entity_id` 的实例
- `include_implicit`：是否允许移除 IMPLICIT/PASSIVE
- `force`：是否忽略 undispellable（用于系统清理/调试）

返回：实际移除数量。

#### 2.2 按 Tag 移除（与 dispel_by_tag 区分：这里是“系统主动移除”，默认也不动 IMPLICIT/PASSIVE）

```gdscript
remove_by_tag(stats, tag_id: String, scope := "ALL", include_implicit := false, force := false) -> int
```

返回：实际移除数量。

#### 2.3 （可选）按来源移除（系统主动移除）

```gdscript
remove_by_source(stats, source_entity_id: int, scope := "ALL", include_implicit := false, force := false) -> int
```

> 与 `dispel_by_source` 类似，但语义上不检查 target_dispel_immunity_mask（免疫只针对“驱散”）。

### 3) 语义约定：主动移除 vs 驱散

- `dispel_*`：战斗规则中的“驱散”，要受 **免疫/不可驱散/implicit/passive** 等语义影响
- `remove_*`：系统层的“强制移除/清理”，默认仍尊重 implicit/passive（避免误删装备等），但可通过参数 override

---

## 稳定顺序与安全性

- 所有批量移除（remove_by_* / dispel_by_*）都必须遍历 `inst_ids.duplicate()`，避免边遍历边修改导致跳过
- `scope="FIRST"` 的“第一个”定义为 **inst_id 最小**（稳定且可复盘）

---

## 测试设计（GUT）

新增测试文件：`tests/rpg/test_buff_removal_a5.gd`，覆盖：

1) **remove_by_buff_id**：移除后 ATK/DEF 回退
2) **remove_by_tag**：移除指定 tag 的实例
3) **移除后事件不再触发**：给 attacker 上 `buff_on_hit_apply_dot`，打一段确认能挂 DOT；移除该 buff 后再打一段，确认不再挂 DOT
4) **inactive 也能移除**：对带条件的 buff（A4）让其 inactive，然后 remove_by_buff_id，确认实例消失且属性不再受影响

---

## 验收标准（A5 第一档）

- 新增 remove_by_* API 可用，且 README/API 约定清晰
- 新增 GUT 用例全绿
- 不破坏既有 A1/A2/A3/A4/DOT/整回合脚本测试

