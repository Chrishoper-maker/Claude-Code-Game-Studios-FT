# 战斗与中枢 UI 改造（4 处）设计

> Story: battle-route-ui-revamp
> 日期：2026-06-27
> 引擎：Godot 4.6.3 / GDScript / GdUnit4
> 范围：4 处用户反馈的交互/布局改进——战斗选中即显示移动、动作按钮浮窗贴角色、选择卡片居中、装备选择可反悔 + 人形纸娃娃。

## 1. 概述（Overview）

四处独立的 UI 改进，集中在战斗 HUD（`player_turn_controller.gd` / `battle_hud.gd`）与中枢白盒屏（`route_scene.gd`）：
1. **选中即显示移动**：点选己方单位后自动高亮可移动范围，不必再点「移动」按钮。
2. **动作按钮浮窗**：移动/攻击/技能/爆发四按钮浮动显示在所选单位旁，不再固定在屏幕底部；单位信息与全局控件移到顶部信息条。
3. **卡片居中**：选航/招募等白盒卡片屏从「偏左上」改为屏幕正中（参考主菜单）。
4. **装备选择可反悔 + 人形纸娃娃**：补装屏候选改为可反复改选、确认后才装；已有装备按人体部位 3 列排布，取代竖排。

均为交互/布局层改动，**不触碰战斗解算、套装效果、数值**，**不引入美术资源**（仍白盒）。

## 2. 玩家体验（Player Fantasy）

点一下船员，能走的格子立刻亮起来，动作按钮就在他身边——指挥更顺手、更少来回找底部按钮。摊开装备面板像穿装备一样按部位摆放，一眼看清头/身/手/脚穿了什么。选卡时内容稳稳居中，不再缩在角落。

## 3. 详细规则（Detailed Rules）

### 3.1 选中即显示移动（#1）
- `PlayerTurnController.select_unit(unit_id)`：成功选中后，若该单位仍可移动（`not has_moved` 且可达格非空）→ `set_mode(Mode.MOVE)`（公开方法，计算可达格 + 高亮）；否则 `_set_mode(Mode.IDLE)`。
- 点绿色可达格 = 移动（既有 `handle_cell_click`/`_do_move` 不变）。
- **攻击仍按钮发起**：浮窗「攻击」→ `set_mode(ATTACK)` 高亮敌 → 点敌执行（既有流程不变）。技能/爆发同既有。
- `cancel()`（Esc）：回到「已选中但 IDLE」（清高亮，不取消选中）。再点同单位或别的己方单位重新进入 MOVE。
- 选中敌方/无效单位：不改变状态（既有 `select_unit` 守卫）。

### 3.2 动作按钮浮窗（#2）
- BattleHUD 拆为两部分：
  - **顶部信息条（固定）**：轮数标签（既有左上）+ 当前单位信息（名/HP/行动点，原 `_info_label`）+ 羁绊槽标签 + 「结束我方回合」按钮。由原底部 `PanelContainer` 迁移到顶部（锚 top，offset 向下）。
  - **浮动动作框**：仅「移动 / 攻击 / 技能 / 爆发」四按钮（`HBoxContainer` 或 `VBoxContainer` 装在一个小 `PanelContainer` 里）。
- **定位**：所选单位世界坐标（`GridCoordMapper.grid_to_world(grid_pos) + Vector3(0,0.75,0)`）经 `get_viewport().get_camera_3d().unproject_position()` 投影到屏幕，浮窗放其旁侧（带固定偏移，做基本屏内夹取防溢出）。
- **可见性**：仅当 `_controller.is_active()`（我方回合且已选中单位）时显示；否则隐藏。
- **刷新**：浮窗在 HUD `refresh()` 时更新按钮可用性与位置；相机/视口变化（`size_changed`）时重新定位。控制器状态变化已经主动调 `refresh()`（既有 `_refresh_hud`）。
- 按钮可用性逻辑沿用 `get_available_actions()`（不变）。

### 3.3 卡片居中（#3）
- `route_scene.gd` 各屏当前用 `box.set_anchors_preset(Control.PRESET_CENTER)`（只设锚点、未设偏移 → 容器自适应尺寸后实际偏左上）。
- 统一改为：内容 `VBoxContainer` 包进一个**撑满全屏的 `CenterContainer`**（`set_anchors_preset(PRESET_FULL_RECT)`），由 CenterContainer 自动把内容居中——与内容尺寸无关、确定性、无需测量。
- 适用屏：`_show_route_offers`、`_show_recruit_offers`、`_show_battle_equip`、`_show_run_end`、`_show_deploy_selection`、`_show_downed_notice`、`_show_recruit_grant_notice`（凡现用 PRESET_CENTER 处）。
- `_clear_ui` 释放逻辑不变（仍释放本中枢所有子节点）。`_active_screen` 标记不变。

### 3.4 装备选择可反悔（#4a）
- `_show_battle_equip` 候选区改为 **toggle 多选**：
  - 每件候选为 `toggle_mode` Button。点选加入 `selected`（高亮 `button_pressed`）、再点移除；可反复改。
  - 最多选 `BATTLE_PICK`(=2) 件：已选满 2 时再点未选项 → `set_pressed_no_signal(false)` 拒绝（不加入）；取消已选项后恢复可选。
  - **「确认」按钮**：`selected` 非空时可点；点击后对每件 `selected` 调 `RunManager.equip_piece(crew_id, eid, occupied)`（占槽则替换），再 `finish_crew_equip`，进入下一名/招募（既有流转）。
  - 选 0 件也可「确认」（等价跳过该船员）→ `finish_crew_equip`。沿用既有 done 流转。
  - 选择期间纸娃娃**预览**：toggle 变化时刷新纸娃娃以「当前 roster 实装 + 已选预览」展示？——MVP 简化：纸娃娃显示**当前实装**（未确认不预览），确认后下一屏自然反映。避免预览态与实装态耦合复杂度。
- 后端 `equip_piece`/`finish_crew_equip`（②b-1）不改。

### 3.5 人形纸娃娃（#4b）
- `_build_paperdoll(crew_id)` 的 9 槽展示由竖排 Label 改为 **3 列 `GridContainer`（columns=3）身体布局**：

  | 左 | 中 | 右 |
  |----|----|----|
  | （空） | 头(2) | 项链(8) |
  | 主武器(0) | 护甲(3) | 副武器(1) |
  | 手(4) | 腿(5) | 戒指(7) |
  | （空） | 靴(6) | （空） |

  （括号内为 slot 枚举值。空位放空 Label 占格保持网格对齐。）
- 每格一个小 `PanelContainer`/Label：文本「部件名\n装备名」，有装备时 `font_color = EquipmentDefinition.rarity_color(rarity)`，空槽显「部件名\n空」。
- 套装档位行（`set_id count/9（已激活 N）✦效果`，②b-2a 既有）仍置于网格上方。
- 此布局同时供补装屏右侧与招募直发通知（`_show_recruit_grant_notice` 也调 `_build_paperdoll`）。

## 4. 组件与文件（Components）

- `src/battle/player_turn_controller.gd`：`select_unit` 改自动进 MOVE（#1）。
- `src/battle/battle_hud.gd`：信息条迁顶部 + 动作按钮浮窗定位（#2）。需相机投影（读 `get_viewport().get_camera_3d()` + `GridCoordMapper`）。
- `src/ui/route_scene.gd`：CenterContainer 居中（#3）+ 补装屏 toggle/确认（#4a）+ `_build_paperdoll` 网格化（#4b）。
- 无新增 autoload/资源。

## 5. 边界情况（Edge Cases）

- #1：选中已耗尽移动的单位 → IDLE（不亮绿格）；浮窗「移动」禁用。
- #1：移动后单位仍选中 → 自动重算（move 已用 → 不再高亮；攻击/技能按需）。
- #2：相机为 null（无头测试）→ 浮窗定位跳过（不崩）；浮窗仅 F5 可见，逻辑层不依赖位置。
- #2：单位在屏幕边缘 → 浮窗夹取进可见区。
- #3：内容超出屏幕（极端长列表）→ CenterContainer 居中，超出部分按需（本项目卡数少，不滚动）。
- #4a：选满 2 后取消一件 → 被拒的候选恢复可选；确认 0 件 = 跳过。
- #4a：两件选中且同槽 → 按选择顺序 equip，后者替换前者同槽（与单件占槽替换一致）；UI 不特别阻止（罕见，候选多为不同槽）。
- #4b：网格空位用空 Label 占位，保证 3 列对齐。

## 6. 依赖（Dependencies）

- `PlayerTurnController`（既有 set_mode/get_available_actions/select_unit）。
- `GridCoordMapper`（grid_to_world，ADR-0006）+ 相机（unproject_position）。
- `RunManager.equip_piece/finish_crew_equip/get_equipment_for/get_set_counts/get_active_set_tier`（②b-1/②b-2a，不改）。
- `EquipmentDefinition.rarity_color`、`SetEffectCatalog.describe`（既有）。
- **不依赖/不改**：BattleResolution、SetEffectSystem、SetBonus、数值数据。

## 7. 可调旋钮（Tuning Knobs）

- 浮窗相对单位的屏幕偏移（px）、屏内夹取边距。
- 顶部信息条高度。
- 纸娃娃格子最小尺寸。

## 8. 验收标准（Acceptance Criteria）

- **AC-1（#1）**：`select_unit` 选中可移动单位后 `get_mode()==MOVE` 且 `get_valid_targets()` 非空；选中已移动单位 → `get_mode()==IDLE`。
- **AC-2（#1）**：攻击流不变——浮窗「攻击」→ ATTACK 模式高亮敌 → 点敌执行（既有测试仍绿）。
- **AC-3（#2）**：BattleHUD 含浮动动作框节点（四动作按钮）与顶部信息条；`is_active()` 为真时浮窗可见、假时隐藏（可测可见性 flag）；按钮可用性沿用 get_available_actions。
- **AC-4（#3）**：route_scene 各卡片屏用 CenterContainer 全屏包裹；`_active_screen` 标记与既有交互测试全绿。
- **AC-5（#4a）**：补装屏候选可 toggle 反复改选；选满 2 拒第三件、取消后恢复；「确认」后才 `equip_piece`；确认前不改 roster 装备（可测：toggle 后未确认时 `get_equipment_for` 不变）。
- **AC-6（#4b）**：`_build_paperdoll` 产出 3 列 GridContainer，9 槽按身体布局放置，空槽占位，装备格带稀有度色。
- **AC-7（回归）**：全量测试 0 错误/失败/孤儿；战斗解算/套装效果行为不变。

## 9. 非目标（本期不做）

- 战斗解算、套装效果、数值平衡的任何改动。
- 美术资源（图标/立绘/动画）；浮窗与纸娃娃仍白盒文字。
- 装备选择期的纸娃娃实时「预览态」（确认前不预览，避免耦合）。
- 手柄/键盘导航浮窗（鼠标点选为主，沿用既有）。
- 攻击的「点敌自动攻击」（用户选定仍按钮发起）。
