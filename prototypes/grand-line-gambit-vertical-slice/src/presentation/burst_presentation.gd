# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: ★最高风险★ set_ignore_time_scale 在 4.6.3 是否按墙钟推进（ADR-0008）
#   + 相机震动局部偏移精确回弹（ADR-0009）。内置墙钟计时日志供验证。
# Date: 2026-06-18
#
# 爆发演出（CanvasLayer layer=10）。订阅 burst_presentation_requested，
# 跑 5 阶段 unscaled Tween；世界走 scaled（FREEZE 减速=定格）。
class_name BurstPresentation
extends CanvasLayer

var _camera: Camera3D
var _tween: Tween
var _t_freeze_start: int = 0

# UI 元素（代码构建）
var _dim: ColorRect
var _panel_left: ColorRect
var _panel_right: ColorRect
var _name_label: Label
var _flash: ColorRect
var _debug_label: Label   # 显示墙钟计时（验证用）

func setup(camera: Camera3D) -> void:
	_camera = camera

func _ready() -> void:
	layer = 10
	_build_ui()
	EventBus.burst_presentation_requested.connect(_on_requested)

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_panel_left = ColorRect.new()
	_panel_left.color = Color("#1A2A3A")
	_panel_left.size = Vector2(640, 360)
	_panel_left.position = Vector2(-700, 120)
	_panel_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_left)

	_panel_right = ColorRect.new()
	_panel_right.color = Color("#3A2A1A")
	_panel_right.size = Vector2(640, 360)
	_panel_right.position = Vector2(1300, 360)
	_panel_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_right)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 96)
	_name_label.add_theme_color_override("font_color", Color("#FFCC00"))
	_name_label.add_theme_color_override("font_outline_color", Color("#CC0000"))
	_name_label.add_theme_constant_override("outline_size", 12)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_label.visible = false
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 18)
	_debug_label.add_theme_color_override("font_color", Color("#00FF88"))
	_debug_label.position = Vector2(16, 16)
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_debug_label)

func _on_requested(lead_id: int, partner_id: int, effect_id: StringName) -> void:
	_start(lead_id, partner_id, effect_id)

func _freeze_scale() -> float:
	# ADR-0008 AC-13/EC-8：≤0 钳制至 0.01 防 P1 永不结束
	if SliceConfig.BURST_TIME_SCALE_FREEZE < 0.01:
		push_warning("BURST_TIME_SCALE_FREEZE 过小，钳制至 0.01")
		return 0.01
	return SliceConfig.BURST_TIME_SCALE_FREEZE

func _start(_lead_id: int, _partner_id: int, effect_id: StringName) -> void:
	EventBus.burst_presentation_started.emit()
	_t_freeze_start = Time.get_ticks_msec()
	Engine.time_scale = _freeze_scale()   # 世界减速；演出 Tween 走 unscaled

	if is_instance_valid(_tween):
		_tween.kill()
	_tween = create_tween()
	# ★ 核心验证：演出按 unscaled 墙钟推进，不受 Engine.time_scale 影响
	_tween.set_ignore_time_scale(true)
	_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)

	# P1 FREEZE（仅计时；世界此刻定格）
	_tween.tween_interval(SliceConfig.BURST_FREEZE_DURATION_MS / 1000.0)
	# P2 PANELS_IN（仍在慢动作世界背景下，演出本身按墙钟）
	_tween.tween_callback(_show_panels)
	_tween.tween_interval(SliceConfig.BURST_PANELS_IN_MS / 1000.0)
	# P3 BURST_NAME
	_tween.tween_callback(_show_name.bind(effect_id))
	_tween.tween_interval(SliceConfig.BURST_NAME_MS / 1000.0)
	# P4 IMPACT：恢复世界时间 + 闪白 + 震屏（AC-4：P4 末 ts==1.0）
	_tween.tween_callback(_impact)
	_tween.tween_interval(SliceConfig.BURST_IMPACT_DURATION_MS / 1000.0)
	# P5 PANELS_OUT
	_tween.tween_callback(_hide_all)
	_tween.tween_interval(SliceConfig.BURST_PANELS_OUT_MS / 1000.0)
	_tween.tween_callback(_finish)

func _show_panels() -> void:
	_dim.color = Color(0, 0, 0, 0.45)
	var t := create_tween().set_ignore_time_scale(true).set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	t.set_parallel(true)
	t.tween_property(_panel_left, "position", Vector2(80, 120), 0.18)
	t.tween_property(_panel_right, "position", Vector2(1120, 360), 0.18)

func _show_name(effect_id: StringName) -> void:
	var names := {
		&"sword_sword": "双剑·斩浪连击",
		&"sword_gunner": "炮火·破阵先锋",
		&"generic": "协力·强击",
	}
	_name_label.text = String(names.get(effect_id, "协力·强击"))
	_name_label.visible = true

func _impact() -> void:
	# ★ 验证点①：打印 P1→P4 墙钟耗时。若 set_ignore_time_scale 生效应 ≈960ms；
	#   若失效（被 0.05 拖慢）会 ≈19200ms。
	var elapsed := Time.get_ticks_msec() - _t_freeze_start
	var expected := int(SliceConfig.BURST_FREEZE_DURATION_MS + SliceConfig.BURST_PANELS_IN_MS + SliceConfig.BURST_NAME_MS)
	_debug_label.text = "[VS验证] P1→P4 墙钟=%d ms（期望≈%d ms / 若失效≈%d ms）" % [
		elapsed, expected, int(expected / _freeze_scale())]
	print(_debug_label.text)

	Engine.time_scale = 1.0   # AC-4：P4 恢复世界正常时间
	# 闪白一帧后淡出
	_flash.color = Color(1, 1, 1, 0.85)
	var ft := create_tween().set_ignore_time_scale(true).set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	ft.tween_property(_flash, "color", Color(1, 1, 1, 0.0), 0.25)
	_shake_camera()

# ── 相机震动（ADR-0009）：Tween 往复局部 position 偏移，末段精确回弹 ──
func _shake_camera() -> void:
	if not is_instance_valid(_camera):
		return  # 场景卸载守卫：跳过震动，演出继续
	var rest: Vector3 = _camera.position
	var vp_h: float = float(_camera.get_viewport().get_visible_rect().size.y)
	if vp_h <= 0.0:
		vp_h = 1080.0
	var amp: float = SliceConfig.BURST_CAMERA_SHAKE_INTENSITY * _world_per_pixel(_camera, GridCoordMapper.board_center(), vp_h)

	var t := create_tween().set_ignore_time_scale(true).set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	var step: float = (SliceConfig.BURST_CAMERA_SHAKE_DURATION_MS / 1000.0) / float(SliceConfig.SHAKE_OSCILLATIONS)
	for i in SliceConfig.SHAKE_OSCILLATIONS:
		var decay: float = 1.0 - float(i) / float(SliceConfig.SHAKE_OSCILLATIONS)
		var local_off: Vector3 = _camera.transform.basis * Vector3(amp * decay, amp * decay, 0.0)
		var sgn: float = 1.0 if i % 2 == 0 else -1.0
		t.tween_property(_camera, "position", rest + local_off * sgn, step)
	t.tween_property(_camera, "position", rest, step)  # ★ 精确回弹，无累积漂移

static func _world_per_pixel(camera: Camera3D, target: Vector3, viewport_height: float) -> float:
	var distance := camera.global_position.distance_to(target)
	var half_fov := deg_to_rad(camera.fov) * 0.5
	return (2.0 * distance * tan(half_fov)) / viewport_height

func _hide_all() -> void:
	_dim.color = Color(0, 0, 0, 0.0)
	_name_label.visible = false
	_panel_left.position = Vector2(-700, 120)
	_panel_right.position = Vector2(1300, 360)

func _finish() -> void:
	Engine.time_scale = 1.0
	EventBus.burst_presentation_ended.emit()

# skip / 重入清理（ADR-0008 规则7/AC-11）
func skip() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	Engine.time_scale = 1.0
	_hide_all()
	EventBus.burst_presentation_ended.emit()
