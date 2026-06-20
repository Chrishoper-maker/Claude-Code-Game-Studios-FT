# 设计规格：玩家回合输入 + 白盒战斗 HUD

> Status: Approved（brainstorming 2026-06-20）
> 目标里程碑：把战斗从"能看不能动"变成"能玩"——玩家可在自己单位回合移动/普攻/职业动词/触发爆发/结束回合。
> 引擎：Godot 4.6.3 / GDScript。配色与布局走白盒（图元 + Control，零 PNG 美术）。

## Overview

`turn_manager` 是**严格先攻队列**（非"我方阶段/敌方阶段"）：单位按先攻值交替激活。每个玩家单位的
`ACTIVE_TURN` = 玩家指挥**当前这一个**被激活的 crew 单位（移动/攻击/动词/结束，行动点三个独立 bool 任意顺序），
不是自由点选"先动谁"。本系统在玩家 `ACTIVE_TURN` 接管输入、把指令翻译成对既有战斗子系统（GridBoard /
BattleResolution / BondGaugeBurst / TurnManager）的调用，并提供白盒 HUD 与棋盘高亮反馈。

本系统**不产生战斗逻辑**——所有效果由既有已测系统执行；本系统只做"输入 → 校验 → 派发 → 视觉反馈"。

## 架构（三节点，方案 A）

挂在 `BattleScene` 下，职责单一、可独立理解与测试：

| 节点 | 类型 | 职责 | 验证 |
|------|------|------|------|
| `PlayerTurnController` | Node（src/battle/player_turn_controller.gd） | 输入状态机 + 合法目标计算 + 动作派发 | **逻辑单测 BLOCKING** |
| `BoardHighlighter` | Node3D（src/board/board_highlighter.gd） | 棋盘格高亮（可达/可攻击/爆发候选） | 视觉 F5 ADVISORY |
| `BattleHUD` | Control（src/ui/battle_hud.gd，挂 HUDLayer CanvasLayer） | 动作栏按钮 + 当前单位状态 + 羁绊槽 + 轮次 | 视觉 F5 ADVISORY |

辅助：`UnitView`（既有）增加 `Label3D` 头顶 HP 显示（订阅 damage/heal 更新）。

### 依赖注入
`PlayerTurnController.setup(turn_manager, grid_board, battle_resolution, bond_gauge_burst, highlighter, hud)`，
由 `BattleScene._ready()` 在既有 setup 序列后接线（DI over singleton，coding-standards）。

## PlayerTurnController（核心，可单测）

### 输入状态机
```
IDLE → MODE_MOVE | MODE_ATTACK | MODE_VERB | MODE_BURST_LEAD → MODE_BURST_PARTNER
```
- 订阅 `EventBus.unit_turn_started(unit_id)`：当前单位 faction=="crew" 且存活 → 接管（_active = true，进 IDLE，刷新可用动作）；enemy → 休眠（_active = false，HUD 显示"敌方回合"，AI 自动跑）。
- 订阅 `unit_turn_ended` / `battle_won` / `battle_lost`：退出接管、清高亮。

### 可测核心接口（不碰鼠标/渲染）
| 方法 | 行为 |
|------|------|
| `set_mode(mode: Mode)` | 计算该模式合法目标集（见下），调 highlighter.show_cells + hud 更新模式标记 |
| `handle_cell_click(cell: Vector2i)` | 若 cell ∈ 当前模式合法目标 → 执行对应动作 → 回 IDLE + 刷新；否则忽略（非法点击无副作用） |
| `end_turn()` | `turn_manager.end_current_turn()` |
| `get_available_actions() -> Dictionary` | { move:bool, attack:bool, verb:bool, burst:bool }（按行动点 + 是否有合法目标 + 槽满）；供 HUD 启用按钮 |
| `cancel()` | 回 IDLE，清高亮（Esc / 点空白） |

### 合法目标计算
- **MODE_MOVE**（!has_moved）：`grid_board.get_reachable_cells(pos, def.move_range)`。
- **MODE_ATTACK**（!has_acted）：`get_alive_enemies()` 过滤 `battle_resolution.is_valid_attack(cur, e)` → 取其格。
- **MODE_VERB**（!has_used_verb 且 class_action_id != ""）：按动词分两类——
  - **无目标**（slash/guard/aura）：点[动词]按钮**立即执行**，不进入持久模式、不需点格（MVP 起始 crew = swordsman(slash)/bulwark(guard)）：slash=`execute_slash(cur)`、guard=`execute_guard(cur, cur)`。执行后回 IDLE、[动词]置灰。
  - **需目标/方向**（cannon/heal/displace）：起始 crew 不涉及，**留接口 TODO**（按 class_action_id 分支，未实现分支断言提示）。
- **MODE_BURST_LEAD**（bond_gauge_burst.is_full()）：高亮 crew ∧ 存活 ∧ !has_acted 的单位格。
- **MODE_BURST_PARTNER**（已选 lead）：高亮 crew ∧ 存活 ∧ !has_used_verb ∧ `GridBoard.chebyshev(lead, c)==1` 的单位格；点选 → `bond_gauge_burst.activate_burst(lead, partner)`。

### 动作执行接线
| 动作 | 调用 |
|------|------|
| 移动 | `grid_board.forced_move_unit(id, cell)`（emit unit_moved，见修复）+ `unit.grid_position = cell` + `turn_manager.mark_has_moved(id)` |
| 普攻 | `battle_resolution.execute_attack(cur, target_id)` |
| 动词 slash | `battle_resolution.execute_slash(cur)` |
| 动词 guard | `battle_resolution.execute_guard(cur, cur)` |
| 爆发 | `bond_gauge_burst.activate_burst(lead, partner)` |

### 视觉壳（F5 验证，非测试）
`_unhandled_input`：鼠标左键 → `get_viewport().get_camera_3d()` → `project_ray_origin/normal(mouse)` → 与 y=0 平面求交（`t = -from.y/dir.y`）→ `GridCoordMapper.world_to_grid(world)` → `handle_cell_click(cell)`。非物理拾取，遵 ADR-0007。Esc → cancel()。
输入锁预留：订阅 `burst_presentation_started/ended` 设幂等布尔 `_locked`，锁定时 _unhandled_input 直接 return（当前演出层 stub 不发这两信号，故暂不触发，预留兼容）。

## BoardHighlighter（纯视觉）

- `show_cells(cells: Array[Vector2i], color: Color)`：从池取 MeshInstance3D（PlaneMesh，y=0.01 防 z-fighting，ADR-0006 高亮规范），定位 `GridCoordMapper.grid_to_world(cell)`，半透明无光材质。
- `clear()`：隐藏全部池节点。
- 颜色约定：move=绿 #22FF66 半透；attack=红 #FF2222 半透；burst 候选=金 #FFCC00 半透。

## BattleHUD（纯视觉，白盒）

挂在既有 `HUDLayer`（CanvasLayer layer=5）下，全 Control 拼装（零美术）：
- **底部动作栏**：`[移动][攻击][动词][爆发][结束回合]` Button。`disabled` 由 `controller.get_available_actions()` 驱动；爆发按钮槽满转金色 modulate。点击 → 调 controller.set_mode / end_turn。
- **当前单位区**：名字 + `HP cur/max` Label + 三行动点指示（移/攻/词，●可用 ○已用）。当前单位为 enemy 时显示"敌方回合"、动作栏整体禁用。
- **羁绊槽**：10 格 ColorRect 条，填充 `bond_gauge_current`；满格末格金色（订阅 gauge_charged / bond_gauge_full / burst_executed）。
- **轮次**：`第 X 轮 / 8` Label（订阅 round_started；last_round_warning 转深红）。
- 订阅 `damage_dealt / heal_executed / unit_turn_started` 等保持显示同步。

## UnitView 头顶 HP（既有类增量）

`UnitView` 增加 `Label3D` 子节点（billboard 朝相机），`set_hp(cur, max)` 更新文本 `cur/max`。
新增订阅在 UnitRenderer：`damage_dealt / heal_executed` → 找对应 view → set_hp。初始 spawn 时设满血。

## 顺手修复：GridBoard 发 unit_moved

**问题**：当前无任何代码 emit `EventBus.unit_moved`，连敌方移动（EnemyAI._apply_move）都不驱动 UnitView 补间。
**修复**：`GridBoard.forced_move_unit(id, dest)` 内，移动前取 from 位置，移动后 `EventBus.unit_moved.emit(id, from, dest)`。
这是 HUD GDD 第182行既定职责（"网格棋盘系统 unit_moved"）。连带让敌方移动也开始补间。
**风险控制**：TDD 加一条 emit 断言；回归验证 EnemyAI 执行测试不因新信号失败（它们不应断言 unit_moved 缺席）。
PlayerTurnController/EnemyAI 移动后仍各自 `mark_has_moved` + 写 `unit.grid_position`（forced_move_unit 只管棋盘占用与信号）。

## 数据流（一个玩家回合）
```
unit_turn_started(阿斩) → Controller 接管 + HUD 亮动作栏（按 available_actions）
  玩家点[移动] → set_mode(MOVE) → 绿格高亮
  点绿格 → handle_cell_click → forced_move_unit(emit unit_moved → UnitView 补间) + mark_has_moved → IDLE，[移动]灰
  玩家点[攻击] → set_mode(ATTACK) → 红格高亮
  点红格(敌) → execute_attack(emit damage_dealt/unit_downed → HP Label/HUD 更新) → IDLE，[攻击]灰
  玩家点[结束回合] → end_turn → turn_manager 推进 → 下一个先攻单位
    若敌方 → enemy_turn_started → AI 同步执行（移动补间异步播放），完成后继续推进，直到下一个玩家单位
```

## 测试策略（coding-standards）

**BLOCKING 单测**（tests/unit/player_turn_controller/、tests/unit/grid_board/）：
- GridBoard.forced_move_unit emit unit_moved(id, from, to)。
- Controller：unit_turn_started(crew) 接管 / unit_turn_started(enemy) 休眠。
- set_mode(MOVE) 合法目标 == get_reachable_cells；set_mode(ATTACK) == is_valid_attack 过滤集。
- handle_cell_click 合法格 → 正确副作用（移动后单位在新格 + has_moved；攻击后目标掉血）；非法格 → 无副作用。
- 动词 slash/guard 执行正确。
- 爆发 lead/partner 选择流程：MODE_BURST_LEAD 候选集、选 lead 后 partner 候选集、合法 partner → activate_burst 被调用且效果生效（端到端用真实 BondGaugeBurst）。
- get_available_actions 随行动点/槽状态变化正确。

**ADVISORY F5**：高亮渲染对齐、HUD 布局/按钮启停、鼠标拾取手感、Label3D HP、敌方移动补间。

## 范围边界（YAGNI，本增量明确不做 → 留后续 story）
- 意图叠层图标/箭头（敌人意图可视化）
- 先攻队列轴 UI
- 伤害/治疗浮字动画（MVP 用 HP Label 直接跳变 + HUD 反馈）
- 爆发华丽演出（burst presentation 仍 stub；爆发只生效逻辑 + HP 变化反馈）
- 所有 PNG 美术资源、职业/状态图标
- status_consumed 等增量信号、键盘快捷键（除 Esc）
- 敌方/全体单位状态面板（只做当前单位区 + 头顶 HP）
- 需目标/方向的动词（cannon/heal/displace）目标选择 UX（起始 crew 不涉及，留接口）

## 验收标准（可玩性）
- **AC-1**：玩家单位 ACTIVE_TURN 时动作栏按可用行动点启用；敌方 ACTIVE_TURN 时禁用并显示"敌方回合"。
- **AC-2**：点[移动]高亮可达格，点格后单位补间移动到该格、[移动]置灰、不可再移动。
- **AC-3**：点[攻击]高亮射程内敌人，点敌后执行普攻、目标 HP 下降、[攻击]置灰。
- **AC-4**：点[动词]，阿斩执行斩（相邻敌受击）、铁壁执行挡（获 GUARDED），[动词]置灰。
- **AC-5**：槽满时爆发按钮转金，点击进入 lead 选择→partner 选择，合法配对触发爆发并生效（HP/状态变化可见）。
- **AC-6**：点[结束回合]推进到下一个先攻单位；敌方单位自动行动后回到下一个玩家单位。
- **AC-7**：Esc 取消当前模式回 IDLE，清除高亮。
- **AC-8**：移动（玩家与敌方）均驱动 UnitView 补间（unit_moved 修复生效）。
