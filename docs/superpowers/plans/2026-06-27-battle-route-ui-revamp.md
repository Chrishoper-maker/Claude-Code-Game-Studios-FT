# 战斗与中枢 UI 改造（4 处）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 4 处 UI 改进——战斗选中即显示移动范围、动作按钮浮窗贴角色、中枢卡片屏居中、装备选择可反悔 + 人形纸娃娃。

**Architecture:** 改 `player_turn_controller.gd`（select_unit 自动进 MOVE）、`battle_hud.gd`（动作按钮浮窗 + 信息条迁顶部，相机投影定位）、`route_scene.gd`（CenterContainer 居中 + 补装屏 toggle/确认 + 纸娃娃 3 列网格）。不碰战斗解算/套装效果/数值/美术。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。战斗 HUD（Control on CanvasLayer）+ 中枢白盒 Control + 相机 unproject_position + GridCoordMapper。

## Global Constraints

- 引擎 Godot 4.6.3；测试 GdUnit4：先 `/Applications/Godot.app/Contents/MacOS/Godot --headless --import`，再 `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a <test path>`。
- 命名：类 PascalCase、变量/函数 snake_case、常量 UPPER_SNAKE_CASE。
- GDScript 静态类型；公共/新增 API 中文 doc 注释。
- 测试 0 孤儿是项目标准：Node 派生对象（GridBoard/TurnManager/...）须 `auto_free()` 或 after_test `free()`。
- 提交 Conventional Commits，body 引用 `Story: battle-route-ui-revamp`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 不改：BattleResolution、SetEffectSystem、SetBonus、RunManager 后端、数值数据。UI 视觉（浮窗定位/居中/人形观感）为 F5-advisory；逻辑（模式/可见性/选择/网格结构）须单测。
- 攻击仍按钮发起（不做点敌自动攻击）。装备确认前纸娃娃不预览。

## File Structure

- `src/battle/player_turn_controller.gd`（改）：`select_unit` 自动进 MOVE。
- `src/battle/battle_hud.gd`（改）：信息条迁顶部 + 浮动动作框 + 相机投影定位。
- `src/ui/route_scene.gd`（改）：各卡片屏 CenterContainer 居中 + 补装屏 toggle/确认 + `_build_paperdoll` 3 列网格。
- 测试：`tests/unit/player_turn_controller/`（改既有）、`tests/unit/battle_hud/`（建）、`tests/integration/battle_equip_ui/`（扩）、`tests/unit/paperdoll/`（建）。

---

### Task 1: 选中即显示移动（#1）

**Files:**
- Modify: `src/battle/player_turn_controller.gd`（`select_unit`）
- Modify: `tests/unit/player_turn_controller/player_turn_controller_test.gd`

**Interfaces:**
- Consumes: 既有 `set_mode(Mode.MOVE)`、`_grid_board.get_reachable_cells`、`UnitInstance.has_moved/get_move_range`。
- Produces: `select_unit` 选中可移动单位后处于 `Mode.MOVE`（高亮可达格）；不可移动则 `Mode.IDLE`。

- [ ] **Step 1: 改既有测试断言（先 RED）**

`tests/unit/player_turn_controller/player_turn_controller_test.gd` 的 `test_select_crew_unit_makes_it_active`（约 51-57 行）末行：

```gdscript
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)
```
改为：
```gdscript
	# #1：选中可移动单位后自动进 MOVE（crew 在 (3,7)、move_range 3、未移动 → 可达非空）
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.MOVE)
	assert_bool(ctx.ctrl.get_valid_targets().is_empty()).is_false()
```

并新增一个不可移动场景测试（放在该函数后）：

```gdscript
func test_select_unit_with_no_move_left_stays_idle() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	ctx.ctrl._on_player_phase_started()
	ctx.tm.mark_has_moved(crew)            # 已移动 → 无可达
	ctx.ctrl.select_unit(crew)
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests/unit/player_turn_controller/player_turn_controller_test.gd`
Expected: `test_select_crew_unit_makes_it_active` FAIL（当前 select_unit 进 IDLE）。

- [ ] **Step 3: 实现**

`player_turn_controller.gd` 的 `select_unit` 改为：

```gdscript
# 选中一个己方单位指挥（点击空闲态下的己方单位格触发）。
# #1：选中即自动展示移动范围（若还能移动），免去再点「移动」。
func select_unit(unit_id: int) -> void:
	var u: UnitInstance = _turn_manager.get_unit(unit_id)
	if u == null or not u.is_alive or u.definition.faction != "crew":
		return
	_selected_unit_id = unit_id
	if not u.has_moved and not _grid_board.get_reachable_cells(u.grid_position, u.get_move_range()).is_empty():
		set_mode(Mode.MOVE)
	else:
		_set_mode(Mode.IDLE)
```

- [ ] **Step 4: 跑测试确认通过 + 全量回归**

Run: `... -a res://tests/unit/player_turn_controller/player_turn_controller_test.gd`
Expected: PASS。
然后全量 `... -a res://tests`，确认 0 失败/错误/孤儿。⚠️ 若别处测试断言「select 后 IDLE」也红，按同样口径诚实更新（可移动→MOVE）；若是真回归则定位。

- [ ] **Step 5: 提交**

```bash
git add src/battle/player_turn_controller.gd tests/unit/player_turn_controller/player_turn_controller_test.gd
git commit -m "feat(battle): auto-enter MOVE mode on unit select

Story: battle-route-ui-revamp
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: 动作按钮浮窗 + 信息条迁顶部（#2）

**Files:**
- Modify: `src/battle/battle_hud.gd`
- Test: `tests/unit/battle_hud/battle_hud_test.gd` (create)

**Interfaces:**
- Consumes: `PlayerTurnController`（is_active/is_phase_active/get_available_actions/get_current_unit_id/set_mode/do_verb/begin_burst_targeting/end_player_phase）、`TurnManager.get_current_round/get_unit`、`GridCoordMapper.grid_to_world`、相机 `unproject_position`。
- Produces: BattleHUD `_action_panel`（浮动动作框，含 4 动作按钮）+ 顶部信息条；`refresh()` 设 `_action_panel.visible = _controller.is_active()` 并定位。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/battle_hud/battle_hud_test.gd`：

```gdscript
# BattleHUD：动作浮窗仅在选中单位时可见；含 4 动作按钮；顶部信息条存在。
extends GdUnitTestSuite

func _make_def(faction: String, unit_class: String, verb: String) -> UnitDefinition:
	var d := UnitDefinition.new()
	d.id = "%s_%s" % [faction, unit_class]
	d.faction = faction; d.unit_class = unit_class
	d.base_damage = 3; d.move_range = 3; d.attack_range = 1; d.max_hp = 10
	d.class_action_id = verb
	return d

func _ctx() -> Dictionary:
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	var br: BattleResolution = auto_free(BattleResolution.new())
	var bb: BondGaugeBurst = auto_free(BondGaugeBurst.new())
	br.setup(gb, tm); bb.setup(gb, tm, br)
	var ctrl: PlayerTurnController = auto_free(PlayerTurnController.new())
	ctrl.setup(tm, gb, br, bb)
	return {"gb": gb, "tm": tm, "br": br, "bb": bb, "ctrl": ctrl}

func test_action_panel_hidden_when_no_selection() -> void:
	var ctx := _ctx()
	var hud: BattleHUD = auto_free(BattleHUD.new())
	add_child(hud)
	hud.setup(ctx.ctrl, ctx.tm)
	hud.refresh()
	assert_bool(hud._action_panel.visible).is_false()

func test_action_panel_visible_with_selection_and_has_four_buttons() -> void:
	var ctx := _ctx()
	var inst := UnitInstance.from_definition(_make_def("crew", "swordsman", "slash"))
	inst.grid_position = Vector2i(3, 7)
	var bid := ctx.tm.register_unit(inst)
	ctx.gb.place_unit(bid, Vector2i(3, 7))
	var hud: BattleHUD = auto_free(BattleHUD.new())
	add_child(hud)
	hud.setup(ctx.ctrl, ctx.tm)
	ctx.ctrl._on_player_phase_started()
	ctx.ctrl.select_unit(bid)
	hud.refresh()
	assert_bool(hud._action_panel.visible).is_true()
	assert_int([hud._btn_move, hud._btn_attack, hud._btn_verb, hud._btn_burst].size()).is_equal(4)

func test_action_panel_hidden_in_enemy_phase() -> void:
	var ctx := _ctx()
	var hud: BattleHUD = auto_free(BattleHUD.new())
	add_child(hud)
	hud.setup(ctx.ctrl, ctx.tm)
	ctx.ctrl._on_player_phase_started()
	ctx.ctrl._on_enemy_phase_started()
	hud.refresh()
	assert_bool(hud._action_panel.visible).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/battle_hud/battle_hud_test.gd`
Expected: FAIL（`_action_panel` 不存在）。

- [ ] **Step 3: 实现 — 重构 _build_ui**

`battle_hud.gd` 增加字段（与现有按钮字段同处）：

```gdscript
var _action_panel: PanelContainer
var _top_bar: PanelContainer
```

把 `_build_ui` 重写为「顶部信息条 + 浮动动作框」（替换原底部 panel 段；保留 _round_label 可并入顶部条）：

```gdscript
func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	if not get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.connect(_on_viewport_resized)

	# 顶部信息条（固定）：轮数 + 单位信息 + 羁绊槽 + 结束我方回合。
	_top_bar = PanelContainer.new()
	_top_bar.anchor_left = 0.0; _top_bar.anchor_right = 1.0
	_top_bar.anchor_top = 0.0; _top_bar.anchor_bottom = 0.0
	_top_bar.offset_top = 0; _top_bar.offset_bottom = 64
	var top_bg := StyleBoxFlat.new()
	top_bg.bg_color = Color(0.06, 0.09, 0.13, 0.92)
	_top_bar.add_theme_stylebox_override("panel", top_bg)
	add_child(_top_bar)
	var top_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		top_margin.add_theme_constant_override("margin_%s" % side, 10)
	_top_bar.add_child(top_margin)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	top_margin.add_child(top_row)
	_round_label = Label.new()
	_round_label.add_theme_font_size_override("font_size", 22)
	top_row.add_child(_round_label)
	_info_label = Label.new()
	_info_label.custom_minimum_size = Vector2(360, 0)
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 20)
	top_row.add_child(_info_label)
	_gauge_label = Label.new()
	_gauge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gauge_label.add_theme_font_size_override("font_size", 20)
	top_row.add_child(_gauge_label)
	_btn_end = _make_button("结束我方回合", func() -> void: _controller.end_player_phase())
	top_row.add_child(_btn_end)

	# 浮动动作框（贴角色）：仅 4 动作按钮。
	_action_panel = PanelContainer.new()
	var act_bg := StyleBoxFlat.new()
	act_bg.bg_color = Color(0.06, 0.09, 0.13, 0.92)
	_action_panel.add_theme_stylebox_override("panel", act_bg)
	add_child(_action_panel)
	var act_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		act_margin.add_theme_constant_override("margin_%s" % side, 6)
	_action_panel.add_child(act_margin)
	var act_box := HBoxContainer.new()
	act_box.add_theme_constant_override("separation", 6)
	act_margin.add_child(act_box)
	_btn_move = _make_button("移动", func() -> void: _controller.set_mode(PlayerTurnController.Mode.MOVE))
	_btn_attack = _make_button("攻击", func() -> void: _controller.set_mode(PlayerTurnController.Mode.ATTACK))
	_btn_verb = _make_button("技能", func() -> void: _controller.do_verb(); refresh())
	_btn_burst = _make_button("爆发", func() -> void: _controller.begin_burst_targeting())
	for b in [_btn_move, _btn_attack, _btn_verb, _btn_burst]:
		act_box.add_child(b)
	_action_panel.visible = false
```

- [ ] **Step 4: refresh() 设可见性 + 定位**

在 `refresh()` 末尾（设完按钮可用性/info 之后）追加：

```gdscript
	_action_panel.visible = _controller.is_active()
	if _action_panel.visible:
		_position_action_panel()
```

并新增定位方法：

```gdscript
# 浮动动作框定位到选中单位的屏幕投影点旁侧（相机为 null 时跳过，不崩）。
func _position_action_panel() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var u: UnitInstance = _turn_manager.get_unit(_controller.get_current_unit_id())
	if u == null:
		return
	var world := GridCoordMapper.grid_to_world(u.grid_position) + Vector3(0, 1.2, 0)
	if cam.is_position_behind(world):
		return
	var screen := cam.unproject_position(world)
	var panel_size := _action_panel.size
	var pos := screen + Vector2(24, -panel_size.y * 0.5)
	# 屏内夹取防溢出。
	var vp := get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - panel_size.x - 8.0))
	pos.y = clampf(pos.y, 72.0, maxf(72.0, vp.y - panel_size.y - 8.0))
	_action_panel.position = pos
```

注：删去 `refresh()` 中对 `_btn_end.disabled` 之外不存在的引用前先确认——`_btn_end` 仍存在（移到顶部条），其 `disabled` 赋值保留。`_btn_move/_btn_attack/_btn_verb/_btn_burst` 仍是成员，可用性赋值逻辑不变。

- [ ] **Step 5: 跑测试确认通过 + 全量回归**

Run: `... -a res://tests/unit/battle_hud/battle_hud_test.gd`
Expected: PASS (3/3)。
然后全量 `... -a res://tests`（含 BattleScene 集成测试，battle_hud.setup 签名未变），确认 0 失败/错误/孤儿。

- [ ] **Step 6: 提交**

```bash
git add src/battle/battle_hud.gd tests/unit/battle_hud/battle_hud_test.gd
git commit -m "feat(ui): floating action panel beside unit + top info bar

Story: battle-route-ui-revamp
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 卡片屏居中（#3）

**Files:**
- Modify: `src/ui/route_scene.gd`

**Interfaces:**
- Produces: 各卡片屏内容包进撑满全屏的 `CenterContainer` → 内容正中。
- Consumes: 无新接口。`_active_screen` 标记、成员引用（`_deploy_buttons`/`_notice_continue_button`/`_deploy_status_label`）不变。

- [ ] **Step 1: 加居中辅助方法**

`route_scene.gd` 加一个 helper（放在 `_clear_ui` 附近）：

```gdscript
# 把内容容器居中：包进撑满全屏的 CenterContainer 后 add 到本中枢。
# 返回传入的内容容器（调用方继续往里加子节点）。
func _add_centered(content: Control) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(content)
	return content
```

- [ ] **Step 2: 各屏改用 _add_centered（替换 set_anchors_preset(PRESET_CENTER) 模式）**

对以下每个方法，把原本的
```gdscript
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER)
```
（或 add_child 与 set_anchors_preset 顺序变体）统一替换为：
```gdscript
	var box := VBoxContainer.new()
	_add_centered(box)
```
涉及方法：`_show_route_offers`、`_show_recruit_offers`、`_show_recruit_grant_notice`、`_show_run_end`、`_show_deploy_selection`、`_show_downed_notice`。
对 `_show_battle_equip`（其根是 `HBoxContainer row`）：把
```gdscript
	var row := HBoxContainer.new()
	add_child(row)
	row.set_anchors_preset(Control.PRESET_CENTER)
```
替换为 `var row := HBoxContainer.new(); _add_centered(row)`。

⚠️ 逐个方法核对实际现有写法后再替换（顺序可能是先 add_child 后 set_anchors，或反之）；只删 add_child+set_anchors_preset 两行、换成 _add_centered，方法内其余逻辑（标题/按钮/子节点）不动。

- [ ] **Step 3: 导入 + 全量回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests`
Expected: 0 失败/错误/孤儿。既有 UI 交互测试（chart_course_ui/run_end_summary/battle_equip_ui/downed_notice/deploy_screen/run_end_unlock_ui）仍绿——它们只断言 `_active_screen` 与成员引用、或递归遍历 Label，CenterContainer 多套一层不影响。

- [ ] **Step 4: 提交**

```bash
git add src/ui/route_scene.gd
git commit -m "fix(ui): center route/card screens via CenterContainer

Story: battle-route-ui-revamp
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 装备选择可反悔 + 确认（#4a）

**Files:**
- Modify: `src/ui/route_scene.gd`（`_show_battle_equip`）
- Test: `tests/integration/battle_equip_ui/battle_equip_toggle_test.gd` (create)

**Interfaces:**
- Consumes: `RunManager.get_pending_battle_equip/equip_piece/finish_crew_equip/get_equipment_for/BATTLE_PICK`、`EquipmentDataManager.get_equipment`、`_equipment_summary`、`_refresh_paperdoll`。
- Produces: `_show_battle_equip` 候选 toggle 多选 + 「确认」后才装；可反复改选；选满 BATTLE_PICK 拒第三件。

- [ ] **Step 1: 写失败测试**

创建 `tests/integration/battle_equip_ui/battle_equip_toggle_test.gd`：

```gdscript
# 补装屏：toggle 可反悔，确认前不改 roster，确认后装；选满 2 拒第三件。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip.clear()
	RunManager._goto_route = func() -> void: pass

func _crew() -> CrewDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition and (d as CrewDefinition).recruit_pool_tier == "starting":
			return d as CrewDefinition
	return null

# 收集补装屏候选 toggle 按钮（递归找 toggle_mode 的 Button）。
func _toggle_buttons(node: Node, out: Array) -> void:
	for ch in node.get_children():
		if ch is Button and (ch as Button).toggle_mode:
			out.append(ch)
		_toggle_buttons(ch, out)

func _confirm_button(node: Node) -> Button:
	for ch in node.get_children():
		if ch is Button and not (ch as Button).toggle_mode and (ch as Button).text == "确认":
			return ch
		var r := _confirm_button(ch)
		if r != null:
			return r
	return null

func test_toggle_defers_equip_until_confirm() -> void:
	var c := _crew()
	RunManager.roster = [c]
	RunManager._pending_battle_equip = {c.id: ["eq_ironwall_head", "eq_ironwall_armor"]}
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	RunManager._phase = RunManager.RunPhase.RUN_EQUIPPING
	route._show_battle_equip()
	assert_str(route._active_screen).is_equal("battle_equip")
	var btns: Array = []
	_toggle_buttons(route, btns)
	assert_int(btns.size()).is_equal(2)
	# 选第一件（经 button_pressed 赋值触发 toggled，无头安全）
	(btns[0] as Button).button_pressed = true
	# 确认前 roster 装备未变
	assert_int(RunManager.get_equipment_for(c.id).size()).is_equal(0)
	# 确认 → 装上
	_confirm_button(route).pressed.emit()
	assert_int(RunManager.get_equipment_for(c.id).size()).is_equal(1)

func test_cannot_select_more_than_pick_limit() -> void:
	var c := _crew()
	RunManager.roster = [c]
	# 三件不同槽候选
	RunManager._pending_battle_equip = {c.id: ["eq_ironwall_head", "eq_ironwall_armor", "eq_ironwall_boots"]}
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	RunManager._phase = RunManager.RunPhase.RUN_EQUIPPING
	route._show_battle_equip()
	var btns: Array = []
	_toggle_buttons(route, btns)
	(btns[0] as Button).button_pressed = true
	(btns[1] as Button).button_pressed = true
	(btns[2] as Button).button_pressed = true   # 第三件应被拒
	assert_bool((btns[2] as Button).button_pressed).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests/integration/battle_equip_ui/battle_equip_toggle_test.gd`
Expected: FAIL（当前候选点击即装、非 toggle）。

- [ ] **Step 3: 实现 — 重写 _show_battle_equip 候选/确认段**

把 `_show_battle_equip` 中「左：候选」循环与 done 按钮段（即从 `for eid in (pending[crew_id] as Array):` 到添加 done 按钮）替换为 toggle + 确认：

```gdscript
	var selected: Array[String] = []        # 已选 eid（≤ BATTLE_PICK）
	for eid in (pending[crew_id] as Array):
		var eq := EquipmentDataManager.get_equipment(str(eid))
		if eq == null:
			continue
		var b := Button.new()
		b.toggle_mode = true
		b.text = _equipment_summary(eq) + "〔%s〕" % eq.set_id
		b.add_theme_color_override("font_color", EquipmentDefinition.rarity_color(eq.rarity))
		b.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				if selected.size() >= RunManager.BATTLE_PICK:
					b.set_pressed_no_signal(false)   # 满 BATTLE_PICK：拒绝
					return
				selected.append(eq.id)
			else:
				selected.erase(eq.id)
			title.text = "为 %s 选至多 %d 件（已选 %d/%d）" % [
				(crew_def as CrewDefinition).display_name if crew_def is CrewDefinition else crew_id,
				RunManager.BATTLE_PICK, selected.size(), RunManager.BATTLE_PICK]
		)
		left.add_child(b)
	var confirm := Button.new()
	confirm.text = "确认"
	confirm.pressed.connect(func() -> void:
		for picked_eid in selected:
			var pdef := EquipmentDataManager.get_equipment(picked_eid)
			var occupied := pdef != null and RunManager.get_equipment_for(crew_id).has(pdef.slot)
			RunManager.equip_piece(crew_id, picked_eid, occupied)
		RunManager.finish_crew_equip(crew_id)
		_clear_ui()
		if RunManager.current_phase == "EQUIPPING":
			_show_battle_equip()        # 下一名
		else:
			_notice_then(_show_recruit_offers)
	)
	left.add_child(confirm)
```
（保留 `title`/`doll_holder`/纸娃娃右侧逻辑不变；纸娃娃确认前不预览——选择期不刷新 doll，确认进入下一屏自然反映。删去原即装 `b.pressed.connect`/原 done 按钮。）

- [ ] **Step 4: 跑测试确认通过 + 全量回归**

Run: `... -a res://tests/integration/battle_equip_ui/battle_equip_toggle_test.gd`
Expected: PASS (2/2)。
然后 `... -a res://tests`（含既有 battle_equip_ui_test，仅断言 _active_screen，仍绿），确认 0 失败/错误/孤儿。

- [ ] **Step 5: 提交**

```bash
git add src/ui/route_scene.gd tests/integration/battle_equip_ui/battle_equip_toggle_test.gd
git commit -m "feat(ui): equip pick is toggle + confirm (re-selectable, deferred equip)

Story: battle-route-ui-revamp
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 人形纸娃娃（3 列网格）（#4b）

**Files:**
- Modify: `src/ui/route_scene.gd`（`_build_paperdoll`）
- Test: `tests/unit/paperdoll/paperdoll_layout_test.gd` (create)

**Interfaces:**
- Consumes: `RunManager.get_set_counts/get_active_set_tier/get_equipment_for`、`SetEffectCatalog.describe`、`EquipmentDefinition.rarity_color`、`_SLOT_NOUNS`。
- Produces: `_build_paperdoll(crew_id)` 返回的 Control 含套装档位行（既有）+ 一个 3 列 `GridContainer`（12 格：9 槽身体布局 + 3 空位）。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/paperdoll/paperdoll_layout_test.gd`：

```gdscript
# 人形纸娃娃：_build_paperdoll 产出含 3 列 GridContainer（12 格）的身体布局。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()

func _crew_id() -> String:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition:
			return (d as CrewDefinition).id
	return ""

func _find_grid(node: Node) -> GridContainer:
	for ch in node.get_children():
		if ch is GridContainer:
			return ch as GridContainer
		var r := _find_grid(ch)
		if r != null:
			return r
	return null

func test_paperdoll_has_three_column_grid_with_twelve_cells() -> void:
	var cid := _crew_id()
	RunManager._roster_equipment[cid] = {2: "eq_ironwall_head"}   # 头槽有装备
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var doll := route._build_paperdoll(cid)
	add_child(doll)            # 进树便于检索（auto_free route 已托管）
	var grid := _find_grid(doll)
	assert_object(grid).is_not_null()
	assert_int(grid.columns).is_equal(3)
	assert_int(grid.get_child_count()).is_equal(12)
	doll.free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests/unit/paperdoll/paperdoll_layout_test.gd`
Expected: FAIL（当前纸娃娃是竖排 Label，无 GridContainer）。

- [ ] **Step 3: 实现 — _build_paperdoll 槽位段网格化**

`_build_paperdoll` 中「9 槽逐行」段（`for slot in range(9):` 加 Label 的部分）替换为构建 3 列网格。保留前面的套装档位行（仍加到外层 `v`）。在档位行之后：

```gdscript
	# 9 槽身体布局（3 列；-1 为空位占格保持对齐）。
	# 行：头/项链 — 主武器/护甲/副武器 — 手/腿/戒指 — 靴
	const _DOLL_LAYOUT := [-1, 2, 8, 0, 3, 1, 4, 5, 7, -1, 6, -1]
	var eq := RunManager.get_equipment_for(crew_id)
	var grid := GridContainer.new()
	grid.columns = 3
	for slot in _DOLL_LAYOUT:
		var cell := Label.new()
		if slot == -1:
			cell.text = ""
		else:
			var def: EquipmentDefinition = eq.get(slot, null)
			if def != null:
				cell.text = "%s\n%s〔%s〕" % [_SLOT_NOUNS[slot], def.display_name, def.set_id]
				cell.add_theme_color_override("font_color", EquipmentDefinition.rarity_color(def.rarity))
			else:
				cell.text = "%s\n空" % _SLOT_NOUNS[slot]
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.custom_minimum_size = Vector2(120, 48)
		grid.add_child(cell)
	v.add_child(grid)
	return v
```
（删去原 `for slot in range(9):` 竖排 Label 段与其后的 `return v`；`const _DOLL_LAYOUT` 可提到文件常量区，若放函数内则用局部 `var`。GDScript 函数内不允许 const → 用 `var _DOLL_LAYOUT := [...]` 或提为类常量。**采用类常量**：把 `const _DOLL_LAYOUT := [-1,2,8,0,3,1,4,5,7,-1,6,-1]` 放到文件常量区（_SLOT_NOUNS 附近），函数内直接引用。）

- [ ] **Step 4: 跑测试确认通过 + 全量回归**

Run: `... -a res://tests/unit/paperdoll/paperdoll_layout_test.gd`
Expected: PASS。
然后 `... -a res://tests`，确认 0 失败/错误/孤儿（补装屏/招募通知调 _build_paperdoll 仍工作）。

- [ ] **Step 5: 提交**

```bash
git add src/ui/route_scene.gd tests/unit/paperdoll/paperdoll_layout_test.gd
git commit -m "feat(ui): humanoid 3-column paper-doll layout

Story: battle-route-ui-revamp
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 全量回归收尾

**Files:**
- （无新文件；汇总验证）

- [ ] **Step 1: 全量回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests`
Expected: 全 PASS，0 errors / 0 failures / 0 orphans。捕获 Overall Summary 行。若红，定位修复（多为某屏 set_anchors 替换遗漏或 _build_paperdoll 调用方）。

- [ ] **Step 2: 提交（若有收尾修复；否则跳过）**

```bash
git add -A
git commit -m "test(ui): full regression green for battle-route UI revamp

Story: battle-route-ui-revamp
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage：**
- §3.1 选中即移动（#1）→ Task 1。✅
- §3.2 动作浮窗 + 信息条迁顶部（#2）→ Task 2。✅
- §3.3 卡片居中（#3）→ Task 3。✅
- §3.4 装备 toggle 可反悔 + 确认（#4a）→ Task 4。✅
- §3.5 人形 3 列纸娃娃（#4b）→ Task 5。✅
- §8 AC-1..7 → Task1(AC1,AC2)/Task2(AC3)/Task3(AC4)/Task4(AC5)/Task5(AC6)/Task6(AC7)。✅
- §9 非目标：不碰战斗解算/套装效果/数值/美术；攻击仍按钮；确认前不预览（Task4 Step3 注明）。✅

**Placeholder 扫描：** 无 TBD/TODO。Task 2/3/4 含「核对实际现有写法后替换」的指示（必要的精确编辑提醒，非占位——给了完整替换代码）。

**类型一致性：** `_action_panel`/`_top_bar`（Task2 定义、测试引用）一致；`_add_centered`（Task3）签名一致；`_DOLL_LAYOUT` 类常量（Task5）；`select_unit` MOVE 行为（Task1 定义、Task2 测试 select 后依赖）一致；`BATTLE_PICK`、`equip_piece`/`finish_crew_equip` 沿用既有签名。

**风险备注（执行者注意）：**
- Task 1 改 `select_unit` 会让任何「select 后断言 IDLE」的测试红——计划只点名 `test_select_crew_unit_makes_it_active`；执行时跑全量，按同口径诚实更新其余（若有），勿弱化。
- Task 2 浮窗定位用相机投影，无头测试相机为 null → `_position_action_panel` 提前返回，测试只断言可见性/按钮存在，不断言像素位置。
- Task 3/4 替换前务必读实际 `route_scene.gd` 对应方法的现有行（add_child 与 set_anchors 顺序、候选/done 段），按相同意图改，勿误删标题/子节点逻辑。
- Task 2/3/4/5 测试用 `auto_free()` 托管 Node（GridBoard/TurnManager/RouteScene/BattleHUD），保持 0 孤儿。
