# 战斗 HUD 系统 (Battle HUD System)

> **Status**: Approved
> **Author**: claude-sonnet-4-6 (autonomous)
> **Last Updated**: 2026-06-16
> **Implements Pillar**: 羁绊即战术（信息透明：让玩家看清战场、做出有意义的选择）；关键回合的爆发（槽满高亮 + 爆发按钮是核心 UI 压力节点）

## Overview

战斗 HUD 系统是《孤帆棋海》战场信息的**透明层**——它将来自战斗解算、回合管理、敌人 AI、羁绊槽与爆发演出五个系统的状态变化实时映射为玩家可读的视觉元素。HUD 本身不产生任何游戏逻辑，它是一块"只读显示器"：订阅上游信号 → 更新显示状态 → 锁定/解锁玩家输入。作为 CanvasLayer 2D 叠层（layer=5），它始终覆盖在 3D 战场之上，并在爆发演出期间被 BurstPresentationLayer（layer=10）覆盖。

HUD 提供六类核心显示区域：**①单位状态面板**（HP条、职业图标、状态效果、行动点）、**②羁绊槽与爆发按钮**（充能进度 + 激活按钮）、**③敌人意图叠层**（格子上的意图图标/箭头）、**④先攻队列轴**（当前轮次的行动顺序）、**⑤轮次计数**（当前轮/上限 + 最后回合预警）、**⑥伤害/治疗浮字**（即时数字反馈）。爆发演出期间 HUD 禁用所有玩家输入但保持可见（被演出层覆盖），演出结束后恢复输入。

## Player Fantasy

好的战场 HUD 是不存在的——玩家不应该感觉到在"读 UI"，而应该感觉到在"读战场"。

当玩家眼睛扫过屏幕，他们看到的不是血条和数字，而是队友还能撑住、那个敌人想冲过来、再两次攻击槽就满了。信息密度是对的：足够让玩家做出完整决策，少到不需要"学习看 HUD"这个额外动作。

**意图全明示**的约定（Into the Breach 契约）在 HUD 层兑现：每个敌方单位的意图图标在 ROUND_START 之后、玩家第一个行动前完整出现。玩家看到这些图标时，应该感觉到"棋局清晰，现在是我的决策时间"——不是焦虑，而是知情的自信。

槽量满格的那一刻是情感峰值之前的预备状态——槽条最后一格闪亮、爆发按钮变为金色，这两个视觉信号应该让玩家心跳加速一下，同时立刻想到"谁和谁还没行动过"。HUD 在这里不只是显示信息，而是在为情感高潮做倒数。

**透明即尊重**：玩家可以在不依赖外部工具的情况下，从屏幕上推算出每个行动的完整后果。如果 HUD 让玩家觉得"我不确定那个数字怎么算出来的"，就是本系统的失职。

## Detailed Design

### Core Rules

---

#### Rule 1：HUD 初始化与销毁

`battle_started()` 信号（由回合管理系统发出）触发 HUD 初始化：
1. 读取所有存活单位数据（`UnitInstance`：unit_id, class_id, faction, max_hp, current_hp, move_range, attack_range）
2. 为每个单位创建对应状态面板（己方在底部面板条，敌方在顶部面板条）
3. 清零羁绊槽显示（`bond_gauge_current = 0`）
4. 隐藏爆发按钮（槽未满）
5. 清空意图叠层（无意图）
6. 重置轮次计数显示为 0 / `ROUND_LIMIT`

`battle_won()` 或 `battle_lost()` 信号触发 HUD 销毁/淡出（具体过渡动画由战后结算系统定义，HUD 仅监听信号并停止响应后续事件）。

---

#### Rule 2：单位状态面板

每个参战单位对应一个状态面板，实时反映其状态：

| 显示元素 | 数据来源 | 更新时机 | 必须可见 |
|---------|---------|---------|---------|
| 职业图标 | `UnitInstance.class_id` | 初始化时一次性设置 | ✓ |
| HP 条（填充比） | `current_hp / max_hp`（Formula 1） | `damage_dealt`、`heal_executed`、`unit_downed` 信号 | ✓ |
| HP 数字 | `current_hp / max_hp` | 同上 | ✓ |
| `GUARDED` 图标 | `unit_statuses` | `guard_applied`、受伤消耗、`ROUND_END` 清理 | ✓ |
| `AURA_BONUS` 图标 | `unit_statuses` | `aura_performed`、攻击消耗 | ✓ |
| **行动点（移动）** | `has_moved` | `unit_moved(unit_id, ...)` 信号（来自 grid-board） | ✓（仅己方） |
| **行动点（攻击）** | `has_acted` | `attack_executed` / `slash_executed` / `cannon_executed` 等（攻击方 attacker_id） | ✓（仅己方） |
| **行动点（动词）** | `has_used_verb` | `slash_executed` / `cannon_executed` / `guard_applied` / `heal_executed` / `displacement_executed` / `aura_performed`（施法方 caster_id） | ✓（仅己方） |
| 高亮边框 | 当前行动单位标记 | `unit_turn_started` / `unit_turn_ended` 信号 | ✓ |
| 击倒标记 | `is_alive == false` | `unit_downed` 信号 | ✓ |

**行动点显示层级**（来自 turn-management UI Requirements 约束）：`has_acted`（攻击/动词）在视觉上须有最高优先级（高亮或优先位置），避免三个行动点平等展示弱化"打谁"是主决策。推荐：攻击图标 > 动词图标 > 移动图标（从左至右降优先级）。

**己方 vs 敌方面板差异**：敌方面板**不显示行动点**（has_moved/has_acted 对玩家意义有限），但显示当前意图图标（见 Rule 5）。

---

#### Rule 3：羁绊槽与爆发按钮

| 状态 | 触发条件 | 显示 |
|------|---------|------|
| 未满（0–9） | `gauge_charged` 更新 | 填充条（分 10 格，填色格 = `bond_gauge_current`）；无动画 |
| 满格（10/10） | `bond_gauge_full` 信号 | 最后一格亮金色闪烁（ `HUD_GAUGE_FULL_FLASH_DURATION` ms）；爆发按钮从灰色变为金色可交互 |
| 爆发激活中 | 玩家点击爆发按钮 → 进入 lead/partner 选择状态 | 按钮"选择中"高亮；Grid 上符合条件的 lead 单位高亮 |
| 爆发执行 | `burst_executed` 信号 | 槽条归零动画（快速清空）；按钮返回灰色 |

**爆发按钮激活条件显示**（辅助指引）：槽满时，鼠标悬停在爆发按钮上显示 tooltip："选择已使用普通攻击的 lead，再选择未使用职业动词的相邻 partner"。此 tooltip 仅在 `bond_gauge_current == BOND_GAUGE_MAX` 时可见。

**爆发效果预览**（`HUD_BURST_TARGETING` 状态）：玩家选定 lead 后，HUD 高亮符合条件的 partner 候选格；每个候选格悬停时显示将触发的爆发技名称（查询 `BURST_EFFECT_TABLE[lead.class][partner.class]`，如"破阵先锋"）和效果摘要。若组合为通用爆发（"generic"），显示"协力强击！"。来源：bond-gauge-burst-system.md 第 359 行约定。

---

#### Rule 4：先攻队列轴

`ROUND_START` 时（build_queue 完成后）HUD 接收回合管理系统的队列数据并渲染先攻轴：

- 显示本轮所有存活单位的行动顺序，按 initiative 降序排列
- 每个单位显示：职业图标 + initiative 整数值（`round(initiative)`；内部排序仍用浮点，UI 取整避免小数噪声）
- 已行动单位：图标变灰（`has_acted OR has_moved OR has_used_verb` 全部完成后视为"本轮结束"）
- 当前行动单位：图标添加活跃光晕
- **tiebreak tooltip**：同 initiative 值的己方单位悬停时显示："同速时，部署顺序靠后的单位优先行动"（来自 turn-management UI Requirements）
- 队列轴位置：屏幕右侧竖排（推荐）；具体布局见 UI Requirements

---

#### Rule 5：敌人意图叠层

`intent_declared(unit_id, intent_record)` 信号触发叠层更新：

| `action_type` | 显示 | 位置 |
|-------------|------|------|
| `INTENT_WAIT` | 等待图标（ZZZ 或护盾） | 敌方单位格子正上方 |
| `INTENT_MOVE` | 移动箭头，指向 `target_pos` | 敌方单位格子 → 目标格 |
| `INTENT_ATTACK` | 攻击图标（剑/准星）+ 红色目标高亮在 `target_pos` 格 | 敌方单位格子正上方 + 目标格叠层 |
| `INTENT_MOVE_ATTACK` | 移动箭头 + 攻击图标；`target_pos`（暂存格）高亮蓝色；攻击目标格高亮红色 | 敌方单位 → 暂存格箭头 + 攻击线 |

`is_stale == true`（意图已过期）时：图标变灰并添加感叹号标记，保持可见直到回合结束（不隐藏，防止信息丢失）。

意图叠层渲染在 `ROUND_START` 信号后（AI 完成声明后）、玩家首个 `ACTIVE_TURN` 开始前展示完整。`ROUND_END` 时清空所有意图叠层。

---

#### Rule 6：轮次计数与最后回合预警

- **轮次计数**：`ROUND_START` 信号时刷新显示为 `"第 {round_count} 轮 / {ROUND_LIMIT}"`
- **最后回合预警**：`last_round_warning()` 信号时触发：
  1. 轮次计数区域红色高亮
  2. 画面顶部横幅："⚠ 下一轮是最后回合！"（持续 `HUD_WARNING_BANNER_DURATION` ms，然后淡出；下方计数区红色保持至战斗结束）

---

#### Rule 7：伤害 / 治疗浮字

| 触发信号 | 浮字内容 | 颜色 | 浮动方向 |
|---------|---------|------|---------|
| `damage_dealt(target_id, final_damage, new_hp)` | `-{final_damage}` | 红色（敌方）/ 橙色（友军受伤） | 从目标格向上飘动 |
| `heal_executed(healer_id, target_id, heal_amount, new_hp)` | `+{heal_amount}` | 绿色 | 从目标格向上飘动 |
| `guard_applied(caster_id, target_id)` | `GUARDED!` | 蓝色 | 从目标格向上飘动 |
| `aura_performed(musician_id, target_ids)` | `AURA!`（每个目标各一个） | 金色 | 从各目标格向上飘动 |
| `displacement_executed(mover_id, caster_id, from_pos, to_pos)` | `↗ 位移` | 青色 | 从 from_pos 格向上飘动；同时在 from_pos→to_pos 之间绘制半透明轨迹高亮（持续 `HUD_FLOAT_DURATION` ms）；若 to_pos 越出棋盘则不浮字（see EC-9 位移边界情况由 battle-resolution 系统处理，`displacement_executed` 不 emit） |

浮字动画时长：`HUD_FLOAT_DURATION` ms（默认 600ms）；同一格同一帧多个浮字自动垂直错开（每个浮字间距 `HUD_FLOAT_OFFSET_Y` px）。

---

#### Rule 8：输入锁定

输入锁定使用**幂等布尔值**（not a counter），遵从 burst-presentation-system.md 约定：

```
locked: bool = false
on burst_presentation_started(burst_type_id):
    locked = true   # idempotent set
on burst_presentation_ended(burst_type_id):
    locked = false  # idempotent clear
```

锁定期间，以下所有玩家输入被忽略（不仅是禁用控件）：
- 格子点选
- 单位选中
- 行动按钮点击（移动/攻击/动词/爆发）
- 结束回合按钮

**炮手弹道友伤警告**（来自 battle-resolution UI Requirements）：玩家选择炮手·轰方向时，HUD 实时高亮弹道路径上的所有单位（含己方），并在有己方单位时显示警告图标。选择期间（非锁定状态）此高亮为实时响应。

### States and Transitions

| 状态 | 描述 | 进入条件 | 退出条件 |
|------|------|---------|---------|
| `HUD_INACTIVE` | HUD 隐藏；战斗未开始 | 初始化 | `battle_started` 信号 |
| `HUD_ROUND_START` | 意图叠层渲染中；玩家等待 | `ROUND_START` 信号（从回合管理） | 所有意图声明完成（AI emit 完毕）；转入 `HUD_IDLE` |
| `HUD_IDLE` | 无单位被选中；等待玩家点选 | 初始化完成 / `unit_turn_ended` / 行动完成 | 点选单位 → `HUD_UNIT_SELECTED`；`burst_presentation_started` → `HUD_LOCKED` |
| `HUD_UNIT_SELECTED` | 单位被选中；显示可移动/攻击范围高亮 | 玩家点选己方单位 | 点选其他格 / 取消 → `HUD_IDLE`；行动完成 → `HUD_IDLE` |
| `HUD_BURST_TARGETING` | 爆发 lead/partner 选择中 | 玩家点击爆发按钮（槽满） | 选择取消 → `HUD_IDLE`；选择完成 → `bond_gauge_burst_system.activate_burst()` → `HUD_IDLE` |
| `HUD_ENEMY_TURN` | 敌方 ACTIVE_TURN；等待 AI 完成 | `enemy_turn_started` 信号 | `unit_turn_ended(unit_id)`（敌方单位）→ `HUD_IDLE`（与友方回合结束使用同一信号，已在 Interactions 表中） |
| `HUD_LOCKED` | 爆发演出中；所有输入禁用 | `burst_presentation_started` 信号 | `burst_presentation_ended` 信号 → `HUD_IDLE` |
| `HUD_BATTLE_OVER` | 战斗结束；HUD 淡出 | `battle_won` 或 `battle_lost` 信号 | 终态；等待场景切换 |

**注**：`HUD_ROUND_START` 状态持续时间极短（AI 同步声明意图），通常在同帧内完成并立即过渡至 `HUD_IDLE`；此状态主要用于保证"意图叠层渲染完成后才允许玩家点选"。

### Interactions with Other Systems

| 系统 | 信号 / 接口 | 方向 | HUD 响应 |
|------|-----------|------|---------|
| 回合管理系统 (#3) | `battle_started()` | 接收 | 初始化所有单位面板，清零槽量，隐藏爆发按钮 |
| 回合管理系统 (#3) | `ROUND_START`（队列数据） | 接收 | 渲染先攻队列轴；进入 `HUD_ROUND_START` 等待意图叠层完成 |
| 回合管理系统 (#3) | `round_ended()` | 接收 | 清空所有意图叠层（Rule 5）；移除所有单位 GUARDED 图标残余（GUARDED 不跨回合，见 battle-resolution Rule 5） |
| 回合管理系统 (#3) | `last_round_warning()` | 接收 | 轮次计数区红色高亮 + 顶部预警横幅 |
| 回合管理系统 (#3) | `battle_won()` | 接收 | 进入 `HUD_BATTLE_OVER`，淡出 HUD |
| 回合管理系统 (#3) | `battle_lost()` | 接收 | 进入 `HUD_BATTLE_OVER`，淡出 HUD |
| 网格棋盘系统 (#2) | `unit_moved(unit_id, from_pos, to_pos)` | 接收 | 更新 has_moved 行动 pip 为"已用"状态（**需回填 grid-board-system GDD 添加此信号**） |
| 网格棋盘系统 (#2) | `get_units_in_direction(pos, dir)` | 调用接口（只读） | 炮手弹道预览实时计算（Rule 8）；不修改棋盘状态 |
| 战斗解算系统 (#4) | `unit_turn_started(unit_id)` | 接收 | 高亮当前单位；显示行动点状态 |
| 战斗解算系统 (#4) | `unit_turn_ended(unit_id)` | 接收 | 移除高亮；先攻轴标记该单位"已行动" |
| 战斗解算系统 (#4) | `enemy_turn_started(unit_id)` | 接收 | 进入 `HUD_ENEMY_TURN`；禁用玩家点选（非锁定，属等待状态） |
| 战斗解算系统 (#4) | `damage_dealt(target_id, final_damage, new_hp)` | 接收 | 更新目标 HP 条 + 浮字 `-{final_damage}` |
| 战斗解算系统 (#4) | `heal_executed(healer_id, target_id, heal_amount, new_hp)` | 接收 | 更新目标 HP 条 + 浮字 `+{heal_amount}` |
| 战斗解算系统 (#4) | `guard_applied(caster_id, target_id)` | 接收 | 在目标面板显示 GUARDED 图标 + 浮字 |
| 战斗解算系统 (#4) | `status_consumed(unit_id, status_type)` | 接收 | 移除对应单位面板的状态图标（status_type: "GUARDED" 或 "AURA_BONUS"）；GUARDED 被伤害消耗时发出，AURA_BONUS 被攻击/斩消耗时发出（**需回填 battle-resolution Interactions 表**） |
| 战斗解算系统 (#4) | `aura_performed(musician_id, target_ids)` | 接收 | 每个目标显示 AURA_BONUS 图标 + 浮字 |
| 战斗解算系统 (#4) | `slash_executed(attacker_id, target_ids, pre_guard_damage)` | 接收 | 斩击动画触发（→ 美术实现；HUD 记录用于浮字去重） |
| 战斗解算系统 (#4) | `cannon_executed(attacker_id, direction, hit_ids, damage)` | 接收 | 弹道路径高亮 + 各命中目标浮字（`damage_dealt` 独立 emit） |
| 战斗解算系统 (#4) | `unit_downed(unit_id)` | 接收 | 面板标记击倒（灰化）；先攻轴移除该单位 |
| 羁绊槽与爆发技系统 (#6) | `gauge_charged(attacker_id, amount, current)` | 接收 | 更新槽条填充格数至 `current` |
| 羁绊槽与爆发技系统 (#6) | `bond_gauge_full()` | 接收 | 最后一格金色闪烁；爆发按钮变为金色可交互 |
| 羁绊槽与爆发技系统 (#6) | `burst_executed(lead_id, partner_id, burst_type_id)` | 接收 | 槽条归零动画；爆发按钮返回灰色 |
| 敌人 AI 与意图系统 (#7) | `intent_declared(unit_id, intent_record)` | 接收 | 在对应敌方单位格渲染意图图标/箭头 |
| 爆发演出系统 (#8) | `burst_presentation_started(burst_type_id)` | 接收 | `locked = true`（幂等布尔锁，见 Rule 8） |
| 爆发演出系统 (#8) | `burst_presentation_ended(burst_type_id)` | 接收 | `locked = false` |
| 玩家输入 | 格子点选、单位选中、行动确认、结束回合 | 接收（从 InputManager） | `locked == true` 时全部忽略；否则驱动 `HUD_UNIT_SELECTED` / `HUD_BURST_TARGETING` 状态 |
| 羁绊槽与爆发技系统 (#6) | `activate_burst(lead_id, partner_id)` | 调用（发出） | `HUD_BURST_TARGETING` 完成选择后调用 |

## Formulas

### 公式 1：HP 条填充比

```
hp_bar_fill = current_hp / max_hp
```

**Variables:**
| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `current_hp` | int | [0, max_hp] | 当前 HP（来自 `damage_dealt` / `heal_executed` 更新） |
| `max_hp` | int | 1–6（MVP 全职业固定 6） | 单位最大 HP（来自 `UnitInstance.max_hp`） |

**Output Range:** [0.0, 1.0]；0.0 = 已 Downed；1.0 = 满血
**Example:** `current_hp=3, max_hp=6 → hp_bar_fill = 0.5`（HP 条填充一半）

---

### 公式 2：羁绊槽填充格数

```
gauge_segments_filled = bond_gauge_current
gauge_fill_ratio = bond_gauge_current / BOND_GAUGE_MAX
```

**Variables:**
| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `bond_gauge_current` | int | [0, BOND_GAUGE_MAX] | 当前槽值（由 `gauge_charged` 信号更新） |
| `BOND_GAUGE_MAX` | int | 10（固定，来自 bond-gauge GDD） | 槽满值 |

**Output Range:** `gauge_segments_filled ∈ {0, 1, …, 10}`（整数格数）
**Example:** `bond_gauge_current=7 → 7格填充，3格空白`

---

### 公式 3：先攻值显示

```
initiative_display = round(initiative_raw)
```

**Variables:**
| 变量 | 类型 | 说明 |
|------|------|------|
| `initiative_raw` | float | 原始先攻值（`move_range×2 + ally_bonus + tiebreak`，来自回合管理系统） |
| `ally_bonus` | float | 有相邻友方时 +0.5（turn-management GDD 约定） |
| `tiebreak` | float | 单位 ID 归一化偏移（防止显示相同值但顺序不一致） |

**Output Range:** 整数（取整后显示），通常 ∈ [2, 10+]
**Example:** `initiative_raw = 7.0005 → initiative_display = 7`（避免小数噪声）

**Note:** 先攻队列内部排序始终使用 `initiative_raw`（浮点精确）；显示层仅取整，不影响排序结果。

---

### 公式 4：浮字错开偏移

当同一格子同一帧发出多个浮字时（如斩击命中多目标），垂直错开：

```
float_y_offset(i) = HUD_FLOAT_OFFSET_Y × i
```

**Variables:**
| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `i` | int | [0, N-1] | 同格浮字的序号（按 emit 顺序） |
| `HUD_FLOAT_OFFSET_Y` | float | 默认 24.0 px | 浮字垂直间距 |

**Output Range:** [0, N×HUD_FLOAT_OFFSET_Y] px 的向上偏移
**Example:** 同帧 3 个浮字 → 偏移 0px / 24px / 48px，从起始点向上错开

## Edge Cases

**EC-1：`damage_dealt` 与 `unit_downed` 同帧到达**
`damage_dealt` 在 `unit_downed` 之前 emit（`resolve_unit_downed` 在步骤 7 才 emit `unit_downed`，此时 `damage_dealt` 早已发出）。HUD 处理顺序：先更新 HP 条至 0 → 再触发击倒标记。不存在"先击倒再显示伤害"的时序问题。

**EC-2：同帧多个 `damage_dealt`（斩击命中多目标）**
`slash_executed` 包含所有目标 ID，但实际 HP 更新来自各自的 `damage_dealt` 信号。HUD 对每个 `damage_dealt` 独立更新对应面板；浮字用 Formula 4 错开偏移；同帧多个面板更新在同一帧完成，不需要队列。

**EC-3：炮手弹道击中己方单位（友伤）**
`damage_dealt(target_id, ...)` 中 target 为己方单位时，浮字颜色用橙色（区别于敌方伤害的红色）。炮手弹道选择阶段，HUD 实时高亮弹道路径上所有单位（含己方），见 Rule 8 炮手预警。

**EC-4：爆发演出期间收到 `gauge_charged` 或 `damage_dealt`**
演出期间 `locked = true`，玩家输入被忽略，但 HUD 仍接收并处理上游信号（HP 条、槽量依然实时更新）。视觉上部分 HUD 元素被 BurstPresentationLayer 覆盖，但 HUD 本身不停止信号处理。

**EC-5：`burst_presentation_started` 连续发出两次（skip 路径）**
因 locked 为幂等布尔值（Rule 8），第二次 started 是 no-op（`locked = true` 已设置）。HUD 不会进入"双重锁定"状态。

**EC-6：槽满时 lead 单位已 `has_acted`（爆发条件不满足）**
`bond_gauge_full()` 仅触发爆发按钮视觉激活；实际激活资格验证由羁绊槽系统负责（在 `activate_burst()` 调用时检查条件）。HUD 在选择 lead 阶段应高亮 `has_acted == false` 的存活己方单位；若所有己方单位均已行动，爆发按钮保持金色外观但选择时显示"无可用 lead"提示，不崩溃。

**EC-7：`unit_downed` 发生在先攻队列显示期间**
先攻队列轴实时响应 `unit_downed`：将该单位图标移除或灰化（不改变已渲染的顺序）。不因单位击倒重建队列轴（本轮队列已建立，新轮次才重建）。

**EC-8：`last_round_warning()` 在 `battle_won()` 同帧发出**
胜利优先（turn-management 设计约束）：`battle_won()` 发出时 HUD 进入 `HUD_BATTLE_OVER`，`last_round_warning()` 的横幅不显示（胜利演出覆盖）。Godot 信号同步执行顺序保证：若 `unit_downed` 触发 `battle_won()`，此事件在 `ROUND_END` 之前发出，因此 `last_round_warning()` 实际不会与 `battle_won()` 同帧。

**EC-9：AURA_BONUS 图标跨回合保留**
`AURA_BONUS` 不在 `ROUND_END` 清除（见 battle-resolution Rule 8）。HUD 对应图标跨回合保留，直到下一次 `attack_executed` 或 `slash_executed` 消耗该状态时（`damage_dealt` 后 HUD 检查状态字典更新图标，或通过独立的 `status_consumed(unit_id, status_type)` 信号——若无此信号，HUD 在 `attack_executed` 后主动查询单位状态字典更新图标）。

**EC-10：战斗结束期间未完成的浮字动画**
`battle_won()` 或 `battle_lost()` 到达时，正在播放的浮字动画立即停止（不等待完成）；HUD 整体淡出。

## Dependencies

### 上游依赖（本系统订阅信号）

| 系统 | GDD | 依赖内容 | 状态 |
|------|-----|---------|------|
| 单位数据系统 (#1) | unit-data-system.md | `UnitInstance`（class_id, faction, max_hp, current_hp, move_range, attack_range, has_moved, has_acted, has_used_verb, is_alive） — 初始化时读取 | Approved |
| 回合管理系统 (#3) | turn-management-system.md | `battle_started`, `ROUND_START`（队列数据）, `last_round_warning`, `battle_won`, `battle_lost`, `unit_turn_started`, `unit_turn_ended`, `enemy_turn_started`, `ROUND_LIMIT` | Approved |
| 战斗解算系统 (#4) | battle-resolution-system.md | `damage_dealt`, `heal_executed`, `guard_applied`, `aura_performed`, `slash_executed`, `cannon_executed`, `displacement_executed`, `unit_downed`；`GUARDED`/`AURA_BONUS` 状态字典查询接口 | In Review |
| 相邻羁绊系统 (#5) | adjacency-bond-system.md | 无直接信号依赖；羁绊加成视觉效果通过 `attack_executed`/`damage_dealt` 的伤害值体现 | Approved |
| 羁绊槽与爆发技系统 (#6) | bond-gauge-burst-system.md | `gauge_charged`, `bond_gauge_full`, `burst_executed`；调用 `activate_burst(lead_id, partner_id)` | Approved |
| 敌人 AI 与意图系统 (#7) | enemy-ai-intent-system.md | `intent_declared(unit_id, intent_record)` — 渲染意图图标/箭头 | Approved |
| 爆发演出系统 (#8) | burst-presentation-system.md | `burst_presentation_started(burst_type_id)` — 锁定输入；`burst_presentation_ended(burst_type_id)` — 解锁输入（幂等布尔锁） | Approved |

### 下游依赖（本系统发出的接口供下游使用）

| 系统 | GDD | 依赖内容 | 状态 |
|------|-----|---------|------|
| 教学系统 (#16) | — | 教学系统可能在 HUD 元素上叠加高亮/提示框；依赖 HUD 节点结构稳定 | Not Started |

### 跨 GDD 合同

**回合管理系统**已在 UI Requirements 节声明本系统须展示的所有信息（先攻队列、行动点、轮次计数、tiebreak tooltip、最后回合预警）——本 GDD 全部实现，无遗漏。

**爆发演出系统**已在 Interactions 松耦合说明中约定：`burst_presentation_started/ended` 须被接收方以幂等布尔处理——本 GDD Rule 8 明确遵从。

**战斗解算系统**已在 UI Requirements 节声明炮手弹道友伤预警为 HUD 职责——本 GDD Rule 8 末段实现。

## Tuning Knobs

| 常量名 | 默认值 | 安全范围 | 游戏效果 | 注册位置 |
|--------|--------|---------|---------|---------|
| `HUD_FLOAT_DURATION` | 600 | [300, 1200] ms | 伤害/治疗浮字飘动时长；过短玩家来不及读数，过长积累过多浮字 | entities.yaml（建议） |
| `HUD_FLOAT_OFFSET_Y` | 24 | [16, 40] px | 同格多浮字垂直间距；过小字符重叠，过大超出格子可视范围 | entities.yaml（建议） |
| `HUD_GAUGE_FULL_FLASH_DURATION` | 800 | [400, 2000] ms | 槽满时最后一格闪烁时长；过长持续干扰视觉，过短玩家可能错过 | entities.yaml（建议） |
| `HUD_WARNING_BANNER_DURATION` | 2000 | [1000, 4000] ms | 最后回合预警横幅显示时长；之后淡出（红色轮次计数保留） | entities.yaml（建议） |
| `HUD_INTENT_ICON_SCALE` | 1.0 | [0.6, 1.5] | 意图图标相对格子大小的缩放系数；1.0 = 格子宽度的约 60% | entities.yaml（建议） |
| `HUD_HP_BAR_TRANSITION_DURATION` | 150 | [0, 400] ms | HP 条变化时的插值动画时长；0 = 即时跳变（无动画），推荐保留轻微过渡感 | entities.yaml（建议） |
| `HUD_LAYER` | 5 | 固定 | CanvasLayer 层级；必须低于 BurstPresentationLayer（layer=10）；建议高于普通 2D 场景（layer=0） | 代码常量 |

**互动约束：**
- `HUD_FLOAT_DURATION` 不应超过 `BURST_PRESENTATION_DURATION_BASE`（1000ms），否则爆发演出期间浮字将延伸到演出层下方（被覆盖但仍在计时，演出结束后残留浮字突然出现）
- `HUD_LAYER < 10`（必须低于 BurstPresentationLayer）——这是硬性架构约束，不可通过旋钮修改

## Visual/Audio Requirements

### 视觉资产（MVP）

| 资产 ID | 类型 | 规格 | 用途 | 里程碑 |
|---------|------|------|------|--------|
| `class_icon_{class}` | Texture2D（PNG） | 64×64 px（建议），共 6 张 | 单位状态面板职业图标 | MVP |
| `intent_icon_wait` | Texture2D | 32×32 px | INTENT_WAIT 图标（ZZZ 或护盾） | MVP |
| `intent_icon_move` | Texture2D | 32×32 px | INTENT_MOVE 图标（脚印/移动箭头） | MVP |
| `intent_icon_attack` | Texture2D | 32×32 px | INTENT_ATTACK 图标（剑/准星） | MVP |
| `intent_icon_move_attack` | Texture2D | 32×32 px | INTENT_MOVE_ATTACK 复合图标 | MVP |
| `intent_arrow` | Texture2D | 方向箭头，可旋转 | 意图移动方向指示 | MVP |
| `status_guarded` | Texture2D | 32×32 px | GUARDED 状态图标（盾牌） | MVP |
| `status_aura_bonus` | Texture2D | 32×32 px | AURA_BONUS 状态图标（音符/光晕） | MVP |
| `gauge_segment_empty` | Texture2D | 9-slice 分段纹理 | 空槽格 | MVP |
| `gauge_segment_filled` | Texture2D | 9-slice 分段纹理 | 填充槽格（普通）  | MVP |
| `gauge_segment_full` | Texture2D | 9-slice 分段纹理 | 槽满状态（金色闪烁变体） | MVP |
| `burst_button_inactive` | Texture2D | 128×48 px（建议） | 爆发按钮未激活状态 | MVP |
| `burst_button_active` | Texture2D | 同上 | 爆发按钮激活（金色）状态 | MVP |
| `action_pip_available` | Texture2D | 16×16 px | 行动点 pip — 可用状态 | MVP |
| `action_pip_used` | Texture2D | 同上 | 行动点 pip — 已用状态 | MVP |
| `warning_banner_bg` | Texture2D / ColorRect | 全宽条带 | 最后回合预警横幅背景 | MVP |

### 字体

| 元素 | 字体风格 | 字号 |
|------|---------|------|
| HP 数字 | 粗体等宽 | 18–24pt |
| 浮字（伤害/治疗） | 粗体斜体 | 28–36pt |
| 轮次计数 | 粗体 | 24pt |
| 预警横幅 | 粗体红色 | 32pt |
| 先攻值 | 常规等宽 | 14pt |

### 颜色约定

| 语义 | 颜色 | 用途 |
|------|------|------|
| 己方伤害浮字（己方受伤） | 橙色 `#FF8800` | 友伤或己方受敌攻击 |
| 敌方伤害浮字 | 红色 `#FF2222` | 敌方 HP 扣减 |
| 治疗浮字 | 绿色 `#22FF66` | 医师·愈 |
| GUARDED 状态 | 蓝色 `#4488FF` | 护盾状态图标和 GUARDED 浮字 |
| AURA_BONUS 状态 | 金色 `#FFCC00` | 光环状态图标 |
| 意图攻击目标高亮 | 红色半透明 | 格子叠层 |
| 意图移动目标高亮 | 蓝色半透明 | 格子叠层 |
| 最后回合预警 | 深红 `#CC0000` | 轮次计数区 + 横幅 |

### 音频资产（MVP 最低要求）

| sfx_id | 触发时机 | 说明 |
|--------|---------|------|
| `sfx_damage_hit` | `damage_dealt` 时 | 普通受击音效（轻） |
| `sfx_unit_downed` | `unit_downed` 时 | 击倒音效 |
| `sfx_gauge_full` | `bond_gauge_full` 时 | 槽满提示音 |
| `sfx_burst_activate` | `burst_executed` 时 | 爆发激活确认音（在 burst_presentation 接手前） |
| `sfx_warning` | `last_round_warning` 时 | 最后回合警报声 |

音频触发由 HUD 系统直接调用 AudioManager，或通过音频系统 (#17) 订阅对应信号（MVP 阶段直接调用即可）。

## UI Requirements

### 屏幕布局（推荐参考）

```
┌─────────────────────────────────────────────────────────┐
│ [敌方面板条 — 顶部]  [round: X/8]  [先攻队列轴 — 右侧] │
│  E1  E2  E3  E4                              U1         │
│ ┌──┐┌──┐┌──┐┌──┐                             U2         │
│ │👹││👹││👹││👹│    [8×8 战场网格]            E1         │
│ └──┘└──┘└──┘└──┘                             U3         │
│  ↙   ⚔   ↑   ZZ                             U4         │  ← 意图叠层
│                                                         │
│                                                         │
│                  [战场]                                  │
│                                                         │
│ ┌──┐┌──┐┌──┐┌──┐                                       │
│ │⚔ ││🛡││💊││🗺│  [████████░░ 羁绊槽 ██] [爆发!]     │
│ └──┘└──┘└──┘└──┘                                       │
│  U1  U2  U3  U4  [行动点 ●●● / ○●○ / ○○●]             │
│ [己方面板条 — 底部]                                     │
└─────────────────────────────────────────────────────────┘
```

以上为参考布局，最终视觉设计由美术/UX 主导；本 GDD 约定**必须呈现的信息区域**，不锁定像素位置。

### 各区域规范

**单位状态面板（己方 — 底部）**：
- 4 个面板水平排列；面板内含：职业图标（左）、HP 条（右上）、HP 数字、行动点 pips（3个：移动/攻击/动词）、状态图标（GUARDED/AURA_BONUS）
- 当前行动单位：面板外框金色高亮
- Downed 单位：整体灰化

**单位状态面板（敌方 — 顶部）**：
- 同上，但省略行动点显示；顶部附近显示意图图标

**羁绊槽区域**：
- 10 格分段条；满格后最后一格闪烁
- 紧邻爆发按钮（按钮在槽条右侧）
- 爆发按钮状态：灰色（未满）/ 金色可点击（满，且非锁定）/ 隐藏（锁定中）

**先攻队列轴（右侧竖列）**：
- 从上到下为本轮行动顺序；已行动图标灰化
- 每格显示：职业图标小版 + initiative 整数
- 当前行动单位添加左侧箭头标记

**意图叠层**：
- 渲染在战场格子正上方（附属于 Grid 坐标系，非固定屏幕坐标）
- INTENT_ATTACK 的目标格用红色半透明正方形标记
- INTENT_MOVE_ATTACK 的暂存格用蓝色半透明标记

**轮次计数（右上角）**：
- 格式："第 X 轮 / 8"；最后回合预警时变深红并附感叹号

**炮手弹道预览**：
- 玩家选择炮手·轰方向时，沿所选方向高亮所有格子上的单位（含己方）；己方单位格显示橙色警告标记

### 键盘快捷键

| 键 | 功能 |
|----|------|
| `Escape` | 取消当前选中 / 返回 HUD_IDLE |
| `Space` | 结束当前单位回合（若行动点用尽或玩家选择跳过） |
| `B` | 开启爆发目标选择（若槽满且非锁定） |
| 方向键 | 移动网格光标（Gamepad 适配预留，非 MVP 强制要求） |

### CanvasLayer 层级约定

| 层 | 名称 | layer 值 | 内容 |
|----|------|---------|------|
| 1 | BattleHUDLayer | 5 | 单位面板、槽条、按钮、浮字、轮次计数 |
| 2 | IntentOverlayLayer | 3 | 意图图标/箭头（附属于格子坐标，可在 HUDLayer 之下） |
| 3 | BurstPresentationLayer | 10（外部） | 演出覆盖层（不由本系统管理） |

## Acceptance Criteria

### 初始化

**AC-1（初始化）**：GIVEN 战斗开始（`battle_started` 发出），WHEN HUD 初始化，THEN 所有参战单位面板以正确 HP（`current_hp == max_hp`）、正确职业图标、所有行动点 pip 可用状态显示；槽条归零；爆发按钮灰色不可交互；意图叠层为空。

### HP 显示

**AC-2（伤害更新）**：GIVEN 某单位 HP = 4，WHEN `damage_dealt(target_id, 2, 2)` 发出，THEN 该单位面板 HP 条立即（或在 `HUD_HP_BAR_TRANSITION_DURATION` ms 内）变为 2/6（33%），HP 数字更新为 "2/6"，浮字 "-2" 从目标格向上飘动（红色或橙色取决于阵营）。

**AC-3（治疗更新）**：GIVEN 某单位 HP = 3，WHEN `heal_executed` 发出 heal_amount=3，THEN HP 条更新至 6/6，浮字 "+3" 绿色飘动。HP 不超过 `max_hp`（公式保证）。

**AC-4（击倒标记）**：GIVEN HP = 1，WHEN `damage_dealt(id, 1, 0)` 后 `unit_downed(id)` 发出，THEN 面板在 HP 更新（0/6）后灰化；先攻队列轴移除/灰化该单位；意图叠层清除该单位图标。

### 槽量与爆发

**AC-5（槽量递增）**：WHEN `gauge_charged(attacker_id, 2, 5)` 发出，THEN 槽条填充格数从当前值更新至 5（第 1–5 格填色，第 6–10 格空白）。

**AC-6（槽满激活）**：WHEN `bond_gauge_full()` 发出，THEN 第 10 格闪烁（持续 `HUD_GAUGE_FULL_FLASH_DURATION`）；爆发按钮变金色可交互；锁定状态 (`locked=true`) 时按钮保持视觉金色但不响应点击。

**AC-7（爆发清零）**：WHEN `burst_executed(lead_id, partner_id, burst_type_id)` 发出，THEN 槽条快速归零动画；按钮返回灰色不可交互。

### 输入锁定

**AC-8（锁定有效）**：GIVEN `burst_presentation_started` 已发出（`locked=true`），WHEN 玩家点击任何格子或按钮，THEN 无任何响应（输入被忽略；不进入 `HUD_UNIT_SELECTED`）。

**AC-9（解锁有效）**：GIVEN `locked=true`，WHEN `burst_presentation_ended` 发出，THEN `locked=false`；下一次格子点选正常触发 `HUD_UNIT_SELECTED`。

**AC-10（幂等锁定）**：GIVEN `locked=true`（已发一次 started），WHEN 第二次 `burst_presentation_started` 发出（skip 路径），THEN `locked` 仍为 true（no-op）；随后 `burst_presentation_ended` 发出后 `locked=false`。验证：连续两次 started + 一次 ended 后，点击格子应正常响应。

### 意图叠层

**AC-11（意图渲染）**：GIVEN `ROUND_START` 完成，WHEN 所有 `intent_declared` 信号接收完毕，THEN 每个存活敌方单位的格子上均显示对应意图图标；INTENT_ATTACK 目标格覆盖红色半透明高亮。

**AC-12（意图清除）**：WHEN `ROUND_END`（下一个 `ROUND_START` 前），THEN 所有意图图标/箭头从格子叠层中移除。

### 先攻队列与轮次

**AC-13（先攻队列）**：GIVEN `ROUND_START` 队列建立，WHEN HUD 更新，THEN 先攻轴按 initiative 降序显示所有存活单位，每单位显示职业图标和 `round(initiative_raw)` 整数值；相同显示值的单位维持内部浮点顺序（不因取整而乱序）。

**AC-14（轮次计数更新）**：WHEN `ROUND_START` 发出（`round_count = 3`），THEN 轮次计数区显示 "第 3 轮 / 8"。

**AC-15（最后回合预警）**：WHEN `last_round_warning()` 发出，THEN 轮次计数区变深红；顶部横幅 "⚠ 下一轮是最后回合！" 显示 `HUD_WARNING_BANNER_DURATION` ms 后淡出；轮次计数区红色保留至战斗结束。

### 炮手弹道

**AC-16（弹道友伤预警）**：GIVEN 玩家选择炮手·轰方向，WHEN 弹道路径上存在己方单位，THEN 该单位格显示橙色警告标记（在确认行动前实时更新）。

### 战斗结束

**AC-17（胜利淡出）**：WHEN `battle_won()` 发出，THEN HUD 进入 `HUD_BATTLE_OVER`；所有玩家输入停止响应；HUD 开始淡出动画（具体由战后结算系统/爆发演出系统定义，HUD 配合）。

**AC-18（失败淡出）**：WHEN `battle_lost()` 发出，THEN 同 AC-17 逻辑。

## Open Questions

**OQ-1（已关闭）**：状态消耗信号机制已决策（design-review BLOCK-2）：battle-resolution 需添加 `status_consumed(unit_id, status_type)` 信号（type: "GUARDED" / "AURA_BONUS"）；HUD 订阅后移除对应图标。需回填 battle-resolution-system.md Interactions 表及其 signals 列表。此信号亦关闭 EC-9 中的"若无此信号"分支。

**OQ-2（先攻队列数据接口）**：HUD 需要在 `ROUND_START` 时获取完整的先攻队列（有序 unit_id 列表 + 各自 initiative_raw）。当前 turn-management-system.md 的信号定义中 `ROUND_START` 信号是否携带队列数据，还是需要 HUD 通过读取接口主动查询？→ turn-management GDD 中明确接口，HUD 设计为订阅方式（若信号携带数据）或初始化时注册 callback。→ 实现阶段与 turn-management 实现者对齐。

**OQ-3（意图叠层坐标系）**：意图图标/箭头渲染在战场格子正上方——这些元素应属于 3D 场景（WorldSpaceCanvas？）还是 CanvasLayer（坐标映射）？考虑到 BurstPresentationLayer 的 CanvasLayer 方案已定，意图叠层建议统一使用 2D CanvasLayer + 格子坐标到屏幕坐标映射（Viewport.get_final_transform() + Camera3D.unproject_position）。→ 立项 ADR-HUD-GRID-OVERLAY（实现阶段）。

**OQ-4（爆发 lead/partner 选择流程 UX）**：`HUD_BURST_TARGETING` 状态下，玩家如何选择 lead 和 partner？方案A：先点 lead 格 → 再点相邻 partner 格；方案B：高亮所有有效 lead，玩家点一个 → HUD 高亮有效 partner → 点第二个确认。两种流程的取消逻辑不同。→ Alpha 试玩后确认；MVP 使用方案A（实现简单）。

**OQ-5（HUD 教学系统接入点）**：教学系统（#16）可能需要在 HUD 元素上叠加高亮箭头或文字气泡（"点击这里"之类）。HUD 节点结构应预留教学叠层的接入方式（信号钩子？节点引用注册？）。→ 教学系统 GDD 阶段决策。
