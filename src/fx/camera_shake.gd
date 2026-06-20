# src/fx/camera_shake.gd
# 相机震屏（Node，ADR-0009）。命中即抖，衰减回弹至基准 local position（精确回弹）。
class_name CameraShake
extends Node

const HIT_INTENSITY: float = 0.15
const SHAKE_DURATION: float = 0.2

var _camera: Camera3D
var _base_position: Vector3
var _time_left: float = 0.0
var _intensity: float = 0.0

func setup(camera: Camera3D) -> void:
	_camera = camera
	if _camera != null:
		_base_position = _camera.position
	if not EventBus.damage_dealt.is_connected(_on_damage):
		EventBus.damage_dealt.connect(_on_damage)

func _on_damage(_target_id: int, _final_damage: int, _new_hp: int) -> void:
	shake(HIT_INTENSITY)

func shake(intensity: float) -> void:
	_intensity = intensity
	_time_left = SHAKE_DURATION

func _process(delta: float) -> void:
	if _camera == null:
		return
	if _time_left <= 0.0:
		_camera.position = _base_position
		return
	_time_left -= delta
	var amp := _intensity * maxf(_time_left, 0.0) / SHAKE_DURATION
	_camera.position = _base_position + Vector3(
		randf_range(-amp, amp), randf_range(-amp, amp), randf_range(-amp, amp))
	if _time_left <= 0.0:
		_camera.position = _base_position
