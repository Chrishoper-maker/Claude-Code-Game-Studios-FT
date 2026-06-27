# 白盒战斗 HUD（Control，挂 HUDLayer CanvasLayer layer=5）。零美术：Button/Label 拼装。
# 只读显示 + 把按钮点击转交 PlayerTurnController。
# 顶部信息条：轮数 + 单位信息 + 羁绊槽 + 结束我方回合。
# 浮动动作框：贴选中单位，仅在选中时可见，含 4 动作按钮。
class_name BattleHUD
extends Control

var _controller: PlayerTurnController
var _turn_manager: TurnManager

var _info_label: Label
var _round_label: Label
var _gauge_label: Label
var _btn_move: Button
var _btn_attack: Button
var _btn_verb: Button
var _btn_burst: Button
var _btn_end_unit: Button
var _btn_end: Button

## 顶部固定信息条。
var _top_bar: PanelContainer
## 浮动动作框（贴选中单位屏幕位置旁侧）。
var _action_panel: PanelContainer

func setup(controller: PlayerTurnController, turn_manager: TurnManager) -> void:
	_controller = controller
	_turn_manager = turn_manager
	_build_ui()
	for sig in ["player_phase_started", "enemy_phase_started", "damage_dealt", "heal_executed",
			"gauge_charged", "bond_gauge_full", "burst_executed", "round_started"]:
		EventBus.connect(sig, _on_any_change)
	refresh()

func _on_any_change(_a = null, _b = null, _c = null) -> void:
	refresh()

func _on_viewport_resized() -> void:
	size = get_viewport().get_visible_rect().size

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
	_btn_end_unit = _make_button("结束", func() -> void: _controller.end_unit_turn(); refresh())
	for b in [_btn_move, _btn_attack, _btn_verb, _btn_burst, _btn_end_unit]:
		act_box.add_child(b)
	_action_panel.visible = false

func _make_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	return b

const _SKILL_NAME := {"slash": "斩", "guard": "挡", "cannon": "轰", "heal": "愈", "aura": "奏", "displace": "移"}

func refresh() -> void:
	if _controller == null:
		return
	_round_label.text = "第 %d 轮" % _turn_manager.get_current_round()
	var actions := _controller.get_available_actions()
	_btn_move.disabled = not actions["move"]
	_btn_attack.disabled = not actions["attack"]
	_btn_verb.disabled = not actions["verb"]
	_btn_burst.disabled = not actions["burst"]
	_btn_burst.modulate = Color("#FFCC00") if actions["burst"] else Color.WHITE
	_btn_end.disabled = not _controller.is_phase_active()
	_btn_end_unit.disabled = not _controller.is_active()
	_gauge_label.text = "羁绊槽: %s" % ("满!" if actions["burst"] else "充能中")
	if _controller.is_active():
		var u: UnitInstance = _turn_manager.get_unit(_controller.get_current_unit_id())
		_btn_verb.text = _SKILL_NAME.get(u.definition.class_action_id, "技能")
		_info_label.text = "%s  HP %d/%d  [移%s 攻%s %s%s]" % [
			u.definition.display_name, u.current_hp, u.get_max_hp(),
			"✓" if u.has_moved else "·", "✓" if u.has_acted else "·",
			_SKILL_NAME.get(u.definition.class_action_id, "技"), "✓" if u.has_used_verb else "·"]
	elif _controller.is_phase_active():
		_btn_verb.text = "技能"
		_info_label.text = "我方回合 — 点击己方单位指挥"
	else:
		_btn_verb.text = "技能"
		_info_label.text = "敌方回合行动中…"
	_action_panel.visible = _controller.is_active()
	if _action_panel.visible:
		_position_action_panel()

## 浮动动作框定位到选中单位的屏幕投影点旁侧（相机为 null 时跳过，不崩）。
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
