# 伤害/治疗浮字 + KO 特效（CanvasLayer 下 Control，纯视觉）。订阅战斗结果信号，把数字飘在单位头顶。
# 位置 = 相机反投影单位世界坐标（HUD GDD OQ-3：2D 层 + unproject_position）。
class_name DamageFloater
extends Control

const FLOAT_DURATION: float = 0.6
const KO_DURATION: float = 0.7
const RISE_PX: float = 44.0
const HEAL_COLOR := Color("#22FF66")

var _unit_renderer: UnitRenderer
var _faction_lookup: Callable

static func damage_color(faction: String) -> Color:
	return Color("#FF8800") if faction == "crew" else Color("#FF2222")

func setup(unit_renderer: UnitRenderer, faction_lookup: Callable) -> void:
	_unit_renderer = unit_renderer
	_faction_lookup = faction_lookup
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not EventBus.damage_dealt.is_connected(_on_damage):
		EventBus.damage_dealt.connect(_on_damage)
	if not EventBus.heal_executed.is_connected(_on_heal):
		EventBus.heal_executed.connect(_on_heal)
	if not EventBus.unit_downed.is_connected(_on_downed):
		EventBus.unit_downed.connect(_on_downed)

func _on_damage(target_id: int, final_damage: int, _new_hp: int) -> void:
	var faction: String = _faction_lookup.call(target_id) if _faction_lookup.is_valid() else "enemy"
	_spawn(target_id, "-%d" % final_damage, damage_color(faction), 40, FLOAT_DURATION, false)

func _on_heal(target_id: int, amount: int) -> void:
	_spawn(target_id, "+%d" % amount, HEAL_COLOR, 40, FLOAT_DURATION, false)

func _on_downed(unit_id: int) -> void:
	_spawn(unit_id, "KO", Color("#FF3333"), 96, KO_DURATION, true)

func _spawn(unit_id: int, text: String, color: Color, font_size: int, duration: float, punch: bool) -> void:
	if _unit_renderer == null:
		return
	var view := _unit_renderer.get_view(unit_id)
	if view == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var world: Vector3 = view.global_position + Vector3(0, 1.6, 0)
	if cam.is_position_behind(world):
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	add_child(label)
	label.position = cam.unproject_position(world) - label.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - RISE_PX, duration)
	tw.tween_property(label, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	if punch:
		label.pivot_offset = label.size * 0.5
		label.scale = Vector2(1.4, 1.4)
		tw.tween_property(label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(label.queue_free)
