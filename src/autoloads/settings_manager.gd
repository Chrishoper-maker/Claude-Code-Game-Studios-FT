# 设置持久化 + 应用（autoload；仿 MetaProgress）。user://settings.json。
# 主音量作用于 Master 总线（index 0，恒存在）；显示模式作用于主窗口。
# （autoload 脚本不声明 class_name：注册名 SettingsManager 即全局单例访问）
extends Node

var master_volume: float = 1.0                  # 线性 0.0–1.0
var fullscreen: bool = false
var _save_path: String = "user://settings.json" # 测试可注入

func _ready() -> void:
	load_settings()
	apply_all()

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	save_settings()

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_window_mode()
	save_settings()

func apply_all() -> void:
	_apply_volume()
	_apply_window_mode()

func _apply_volume() -> void:
	var muted := master_volume <= 0.0
	AudioServer.set_bus_mute(0, muted)                  # 0 音量 → 静音，规避 -inf dB
	if not muted:
		AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))

func _apply_window_mode() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

func to_dict() -> Dictionary:
	return {"master_volume": master_volume, "fullscreen": fullscreen}

func from_dict(d: Dictionary) -> void:
	master_volume = clampf(float(d.get("master_volume", 1.0)), 0.0, 1.0)
	fullscreen = bool(d.get("fullscreen", false))

func _set_defaults() -> void:
	master_volume = 1.0
	fullscreen = false

func save_settings() -> void:
	var f := FileAccess.open(_save_path, FileAccess.WRITE)
	if f == null:
		push_error("SettingsManager.save_settings: 无法写入 %s" % _save_path)
		return
	f.store_string(JSON.stringify(to_dict()))
	f.close()

func load_settings() -> void:
	if not FileAccess.file_exists(_save_path):
		_set_defaults()
		return
	var f := FileAccess.open(_save_path, FileAccess.READ)
	if f == null:
		push_error("SettingsManager.load_settings: 无法读取 %s" % _save_path)
		_set_defaults()
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		from_dict(parsed as Dictionary)
	else:
		push_error("SettingsManager.load_settings: 解析失败，置默认")
		_set_defaults()
