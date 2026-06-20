# src/ui/battle_result_overlay.gd
# 胜负结算页（Control，挂高层 CanvasLayer）。战斗终态显示结果 + 重新开始。
class_name BattleResultOverlay
extends Control

var _title: Label

func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	_build_ui()
	visible = false
	if not EventBus.battle_won.is_connected(_on_won):
		EventBus.battle_won.connect(_on_won)
	if not EventBus.battle_lost.is_connected(_on_lost):
		EventBus.battle_lost.connect(_on_lost)

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 72)
	box.add_child(_title)

	var btn := Button.new()
	btn.text = "重新开始"
	btn.custom_minimum_size = Vector2(160, 56)
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(func() -> void: get_tree().reload_current_scene())
	box.add_child(btn)

func _on_won() -> void:
	_show("胜利!", Color("#FFD24A"))

func _on_lost() -> void:
	_show("失败…", Color("#FF5555"))

func _show(text: String, color: Color) -> void:
	_title.text = text
	_title.add_theme_color_override("font_color", color)
	visible = true
