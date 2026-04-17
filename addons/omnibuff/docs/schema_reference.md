# OmniBuff Schema Reference（数据协议速查 + 常见配方）

> 目的：让你在写 `enums.json / stat_defs.json / buff_defs.json` 时不用翻代码。  
> 注意：本文是“速查 + recipes”，不是完整协议说明；以 validators 与 tests 为准。

## 1) enums.json（枚举/白名单）

文件：`res://data/*/enums.json`

常用枚举（节选）：

- `event_type`：`DAMAGE` / `DOT` / `COMMAND` / `LIFE`
- `event_phase`（按 event_type 语义复用）：
  - `DAMAGE`: `BUILD/BEFORE_DEAL/BEFORE_TAKE/RESOLVE/APPLY/AFTER_DEAL/AFTER_TAKE`
  - `DOT`: `TURN_START/TURN_END`（tick 时机）
  - `COMMAND`: `BEFORE/AFTER`
  - `LIFE`: `DEATH/REVIVE`
- `action_kind`（节选）：
  - `ADD_BASE_DAMAGE`
  - `APPLY_BUFF` / `CHANCE_APPLY_BUFF`
  - `HEAL` / `ADD_SHIELD`
  - `DISPEL`
  - `BONUS_DAMAGE`
  - `ADD_STACKS` / `SET_STACKS`
  - `DOT_MUL_STACKS/DOT_ADD_STACKS/DOT_SET_STACKS/DOT_CLEAR`
- `op_type`：`ADD/MUL/OVERRIDE`
- `apply_phase`：`FLAT/PERCENT/FINAL`（当前实现重点用到这些）
- `stack_mode`：`REPLACE/ADD_STACK/MULTI_INSTANCE`

---

## 2) stat_defs.json（属性定义）

文件：`res://data/*/stat_defs.json`

### 2.1 基础字段

```jsonc
{ "id": "HP", "default": 100.0, "min": 0.0, "max": 99999.0, "clamp": true }
```

- `id`：字符串 stat id（通过 `ds.stat_id("HP")` 映射为 int）
- `default`：默认 base
- `clamp/min/max`：最终值 clamp（在曲线之后执行）

### 2.2 Phase 2：derived（派生/转换）

LINEAR（常用）：

```jsonc
{
  "id": "HP",
  "default": 100.0,
  "clamp": true,
  "min": 0.0,
  "max": 99999.0,
  "derived": { "type": "LINEAR", "from": "STR", "ratio": 20.0, "round": "NONE" }
}
```

语义（当前实现最小集）：`HP.base += STR.final * ratio`（叠加到 base，而不是覆盖）。

### 2.3 Phase 2：curve（曲线/DR）

DR_SOFTCAP（递减收益）：

```jsonc
{
  "id": "DMG_REDUCE_RATING",
  "default": 0.0,
  "clamp": true,
  "min": 0.0,
  "max": 0.95,
  "curve": { "type": "DR_SOFTCAP", "k": 100.0, "apply_at": "POST_FINAL" }
}
```

语义：`f(x)=x/(x+k)`，在 clamp 前应用。

---

## 3) buff_defs.json（Buff 定义）

文件：`res://data/*/buff_defs.json`

### 3.1 最小结构

```jsonc
{
  "id": "buff_xxx",
  "name": "xxx",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [
    { "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 10.0 }
  ],
  "triggers": []
}
```

### 3.2 triggers 结构

```jsonc
{
  "event_type": "DAMAGE",
  "event_phase": "AFTER_TAKE",
  "scope": "SELF",
  "filters": { "require_hit": true },
  "action": { "kind": "HEAL", "value": 30.0 }
}
```

常用 filters（节选）：
- `tag_mask_any`
- `require_hit` / `require_crit`
- `skill_id`
- `damage_type_any` / `element_any`
- `require_not_bonus_damage`（BONUS_DAMAGE guard）
- `min_absorbed_shield` / `min_final_damage`
- `stat_threshold`
- LIFE 专用：`actor_id` / `source_id`

---

## 4) 常见配方（recipes）

> 下面示例只给关键字段，省略 name/tags 等常规字段；建议在 `rpg_tests` 里先跑通。

### 4.1 BONUS_DAMAGE（不递归）

```jsonc
{
  "event_type": "DAMAGE",
  "event_phase": "AFTER_DEAL",
  "scope": "TARGET",
  "filters": { "require_hit": true, "require_not_bonus_damage": true },
  "action": { "kind": "BONUS_DAMAGE", "ratio": 0.5, "tags_mask_any": ["BONUS_DAMAGE"], "scope": "TARGET" }
}
```

### 4.2 复活清 DEBUFF（LIFE REVIVE + DISPEL）

```jsonc
{
  "event_type": "LIFE",
  "event_phase": "REVIVE",
  "scope": "SELF",
  "filters": {},
  "action": { "kind": "DISPEL", "mode": "BY_TAG", "tag": "DEBUFF" }
}
```

### 4.3 死亡击杀回血（LIFE DEATH + HEAL scope=SOURCE）

```jsonc
{
  "event_type": "LIFE",
  "event_phase": "DEATH",
  "scope": "SOURCE",
  "filters": {},
  "action": { "kind": "HEAL", "value": 50.0 }
}
```

### 4.4 命中后减少某 debuff 层数（ADD_STACKS delta=-1）

```jsonc
{
  "event_type": "DAMAGE",
  "event_phase": "AFTER_TAKE",
  "scope": "SELF",
  "filters": { "require_hit": true },
  "action": { "kind": "ADD_STACKS", "buff_id": "buff_some_debuff", "delta": -1, "min_stack": 0 }
}
```

### 4.5 命中后直接清除某 debuff（SET_STACKS value=0）

```jsonc
{
  "event_type": "DAMAGE",
  "event_phase": "AFTER_TAKE",
  "scope": "SELF",
  "filters": { "require_hit": true },
  "action": { "kind": "SET_STACKS", "buff_id": "buff_some_debuff", "value": 0 }
}
```

