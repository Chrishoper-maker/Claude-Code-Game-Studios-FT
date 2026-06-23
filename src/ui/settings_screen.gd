# 设置界面（白盒 Control）。主音量 ±10% + 显示模式切换 + 返回。
# 导航经可注入 _nav_back 接缝（DI over singleton），测试覆盖为 no-op。
class_name SettingsScreen
extends Control

const VOL_STEP := 0.1

var _volume_label: Label = null
var _vol_down_button: Button = null
var _vol_up_button: Button = null
var _window_button: Button = null
var _back_button: Button = null

var _nav_back: Callable
func _default_back() -> void: SceneManager.goto_main_menu()

func _ready() -> void:
	_nav_back = _default_back
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER)
	var title := Label.new()
	title.text = "设置"
	box.add_child(title)
	_volume_label = Label.new()
	box.add_child(_volume_label)
	_vol_down_button = Button.new()
	_vol_down_button.text = "主音量 －"
	_vol_down_button.pressed.connect(_on_vol_down)
	box.add_child(_vol_down_button)
	_vol_up_button = Button.new()
	_vol_up_button.text = "主音量 ＋"
	_vol_up_button.pressed.connect(_on_vol_up)
	box.add_child(_vol_up_button)
	_window_button = Button.new()
	_window_button.pressed.connect(_on_window_toggle)
	box.add_child(_window_button)
	_back_button = Button.new()
	_back_button.text = "返回"
	_back_button.pressed.connect(_on_back)
	box.add_child(_back_button)
	_refresh()

# 按 SettingsManager 当前值刷新音量标签与显示模式按钮文案。
func _refresh() -> void:
	_volume_label.text = "主音量：%d%%" % int(round(SettingsManager.master_volume * 100.0))
	_window_button.text = "显示模式：全屏" if SettingsManager.fullscreen else "显示模式：窗口"

func _on_vol_up() -> void:
	SettingsManager.set_master_volume(clampf(SettingsManager.master_volume + VOL_STEP, 0.0, 1.0))
	_refresh()

func _on_vol_down() -> void:
	SettingsManager.set_master_volume(clampf(SettingsManager.master_volume - VOL_STEP, 0.0, 1.0))
	_refresh()

func _on_window_toggle() -> void:
	SettingsManager.set_fullscreen(not SettingsManager.fullscreen)
	_refresh()

func _on_back() -> void:
	_nav_back.call()
