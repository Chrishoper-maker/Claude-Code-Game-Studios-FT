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
	# 先设阶段再 add_child，避免 _ready() 走 IDLE→start_run 污染 _roster_equipment。
	RunManager._phase = RunManager.RunPhase.RUN_EQUIPPING
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	# _ready() 已通过 EQUIPPING 分支调用 _show_battle_equip()，无需再次显式调用。
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
	# 先设阶段再 add_child，避免 _ready() 走 IDLE→start_run 污染状态。
	RunManager._phase = RunManager.RunPhase.RUN_EQUIPPING
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var btns: Array = []
	_toggle_buttons(route, btns)
	(btns[0] as Button).button_pressed = true
	(btns[1] as Button).button_pressed = true
	(btns[2] as Button).button_pressed = true   # 第三件应被拒
	assert_bool((btns[2] as Button).button_pressed).is_false()
