# 浮窗「结束本角色」按钮设计

> Story: end-unit-turn
> 日期：2026-06-27
> 引擎：Godot 4.6.3 / GDScript / GdUnit4
> 前置：battle-route-ui-revamp（浮动动作框，HEAD=afabefd，已 push origin/main）

## 1. 概述（Overview）

战斗浮动动作框（现有移/攻/技/爆 4 按钮）增加第 5 个「结束」按钮。点击后**当前选中角色本回合行动结束**——三项行动点（移动/攻击/技能）全部锁定，本我方回合内不能再行动；棋盘上该角色变灰标记。已结束角色仍可点选查看信息，但浮窗所有动作按钮禁用。新我方回合开始时行动点重置、变灰解除。顶部「结束我方回合」（结束整阶段）保留不变。

## 2. 玩家体验（Player Fantasy）

指挥完一名船员后，点「结束」让他就地待命——他变灰、不再响应，玩家专注调度剩下的人，不会误点已安排好的单位。一眼看清谁已待命、谁还能动。

## 3. 详细规则（Detailed Rules）

### 3.1 结束本角色
- 浮窗新增「结束」按钮 → `PlayerTurnController.end_unit_turn()`。
- `end_unit_turn()`：仅当我方回合中且有选中单位时生效——把选中单位的 `has_moved`/`has_acted`/`has_used_verb` 全标记为真（经 TurnManager.mark_has_*），emit `EventBus.unit_turn_ended(unit_id)`，清空选中，回 IDLE（触发 HUD refresh）。
- 锁定后该单位 `get_available_actions` 全 false（复用现有逻辑，无需新标志）。

### 3.2 已结束角色的再选中
- 仍可点选（顶部信息条显示其 HP/行动点状态）。
- 因三行动点已满，`select_unit` 不进 MOVE（has_moved 真）→ 进 IDLE；浮窗移/攻/技/爆/结束全禁用。
- 即"可看不可动"，与现有"行动点自然用完"表现一致。

### 3.3 变灰标记（视觉）
- `UnitView.set_dimmed(enabled: bool)`：`modulate` 置灰（如 Color(0.5,0.5,0.5)）/ 复原 Color.WHITE。
- `UnitRenderer.set_unit_dimmed(battle_id, enabled)`：转调对应 view。
- `UnitRenderer` 订阅 `EventBus.unit_turn_ended` → `set_unit_dimmed(id, true)`；订阅 `EventBus.player_phase_started` → 所有 view `set_dimmed(false)`（新回合解除）。
- 变灰与「选中高亮」(`set_selected`) 视觉兼容：选中已结束单位时高亮可叠加在灰底上（边框/通道分离）；不互相清除。

### 3.4 恢复时机
- 新我方回合 `player_phase_started`：TurnManager 已 `_reset_action_flags`（三标志重置→单位又能动），UnitRenderer 同步解除全部变灰。
- 敌方回合不影响（变灰跨敌方回合保留到下一我方回合开始）。

## 4. 组件与文件（Components）

- `src/battle/player_turn_controller.gd`：新增 `end_unit_turn()`。
- `src/ui/battle_hud.gd`：浮窗加「结束」按钮 + refresh 设其可用性。
- `src/render/unit_view.gd`：新增 `set_dimmed`。
- `src/render/unit_renderer.gd`：新增 `set_unit_dimmed` + 订阅 unit_turn_ended / player_phase_started。

## 5. 边界情况（Edge Cases）

- 无选中单位 / 非我方回合点「结束」：`end_unit_turn` 守卫 return（按钮本就禁用，双保险）。
- `unit_turn_ended` 信号当前无其他订阅方（实现期 grep 确认）→ 新增 emit 无副作用。
- 已结束单位被敌方击倒：`unit_downed` → UnitView.set_downed 隐藏（既有），dim 不冲突（已隐藏）。
- 爆发（lead/partner）涉及两个单位：本按钮只结束当前选中单位；爆发流程不变。
- 变灰单位在新我方回合自动恢复（player_phase_started）；若该单位已阵亡则无 view（get_view null 守卫）。

## 6. 依赖（Dependencies）

- `PlayerTurnController`（mark via TurnManager / _set_mode / is_active）。
- `TurnManager.mark_has_moved/acted/used_verb`、`get_unit`、`_reset_action_flags`（既有，新回合重置）。
- `EventBus.unit_turn_ended`（已定义，本期首次 emit）、`player_phase_started`（既有）。
- `UnitRenderer`/`UnitView`（既有渲染层）。
- **不改**：战斗解算、套装效果、回合状态机转换、数值。

## 7. 可调旋钮（Tuning Knobs）

- 变灰 modulate 颜色/强度。
- 「结束」按钮标签（默认「结束」）。

## 8. 验收标准（Acceptance Criteria）

- **AC-1**：`end_unit_turn` 后选中单位 has_moved/has_acted/has_used_verb 全真、选中清空（-1）、mode IDLE，并 emit `unit_turn_ended(该id)`。
- **AC-2**：已结束单位再 `select_unit` 后 `get_available_actions` 四项全 false。
- **AC-3**：无选中 / 非我方回合调 `end_unit_turn` 无效果（不报错、不发信号）。
- **AC-4**：BattleHUD 浮窗含「结束」按钮；`is_active()` 时可用、否则禁用。
- **AC-5（视觉/F5-advisory）**：结束→单位变灰；新我方回合→恢复。
- **AC-6（回归）**：全量 0 错误/失败/孤儿；现有回合/HUD 行为不变。

## 9. 非目标（本期不做）

- 「撤销结束」/反悔（结束即锁定到回合末）。
- 已结束单位的额外 HUD 列表/计数。
- 敌方单位的等价机制（敌方由 AI 自动行动，无需）。
- 变灰之外的美术/音效。
