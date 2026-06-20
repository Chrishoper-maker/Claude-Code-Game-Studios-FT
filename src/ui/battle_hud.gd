# 白盒战斗 HUD（Control，挂 HUDLayer CanvasLayer layer=5）。零美术：Button/Label 拼装。
# 只读显示 + 把按钮点击转交 PlayerTurnController。
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
var _btn_end: Button

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
	# CanvasLayer 下的 Control 不会自动铺满视口 → 显式撑满（否则 size=0，锚点子节点错位）。
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	if not get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.connect(_on_viewport_resized)

	_round_label = Label.new()
	_round_label.position = Vector2(20, 16)
	_round_label.add_theme_font_size_override("font_size", 22)
	add_child(_round_label)

	# 底部实心面板（带背景，醒目）：左侧当前单位信息 + 动作按钮 + 槽。
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -72
	panel.offset_bottom = 0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.09, 0.13, 0.92)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	panel.add_child(margin)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(bar)

	_info_label = Label.new()
	_info_label.custom_minimum_size = Vector2(300, 0)
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 20)
	bar.add_child(_info_label)

	_btn_move = _make_button("移动", func() -> void: _controller.set_mode(PlayerTurnController.Mode.MOVE))
	_btn_attack = _make_button("攻击", func() -> void: _controller.set_mode(PlayerTurnController.Mode.ATTACK))
	_btn_verb = _make_button("技能", func() -> void: _controller.do_verb(); refresh())
	_btn_burst = _make_button("爆发", func() -> void: _controller.begin_burst_targeting())
	_btn_end = _make_button("结束我方回合", func() -> void: _controller.end_player_phase())
	for b in [_btn_move, _btn_attack, _btn_verb, _btn_burst, _btn_end]:
		bar.add_child(b)

	_gauge_label = Label.new()
	_gauge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gauge_label.add_theme_font_size_override("font_size", 20)
	bar.add_child(_gauge_label)

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
	_gauge_label.text = "羁绊槽: %s" % ("满!" if actions["burst"] else "充能中")
	if _controller.is_active():
		var u: UnitInstance = _turn_manager.get_unit(_controller.get_current_unit_id())
		_btn_verb.text = _SKILL_NAME.get(u.definition.class_action_id, "技能")
		_info_label.text = "%s  HP %d/%d  [移%s 攻%s %s%s]" % [
			u.definition.display_name, u.current_hp, u.definition.max_hp,
			"✓" if u.has_moved else "·", "✓" if u.has_acted else "·",
			_SKILL_NAME.get(u.definition.class_action_id, "技"), "✓" if u.has_used_verb else "·"]
	elif _controller.is_phase_active():
		_btn_verb.text = "技能"
		_info_label.text = "我方回合 — 点击己方单位指挥"
	else:
		_btn_verb.text = "技能"
		_info_label.text = "敌方回合行动中…"
