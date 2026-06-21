# 主菜单（启动场景，白盒 Control）。标题 + 悬赏解锁进度 + 出航 + 退出。
# 导航/退出经可注入 Callable 接缝（DI over singleton），测试覆盖为 no-op。
class_name MainMenu
extends Control

var _set_sail_button: Button = null
var _quit_button: Button = null
var _unlock_label: Label = null

var _nav_set_sail: Callable
var _nav_quit: Callable
func _default_set_sail() -> void: SceneManager.goto_route()
func _default_quit() -> void: get_tree().quit()

func _ready() -> void:
	_nav_set_sail = _default_set_sail
	_nav_quit = _default_quit
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER)
	var title := Label.new()
	title.text = "《孤帆棋海》"
	box.add_child(title)
	_unlock_label = Label.new()
	_unlock_label.text = "悬赏解锁 %d / %d" % [MetaProgress.unlocked_crew_ids.size(), MetaProgress.get_unlock_order().size()]
	box.add_child(_unlock_label)
	_set_sail_button = Button.new()
	_set_sail_button.text = "出航"
	_set_sail_button.pressed.connect(_on_set_sail)
	box.add_child(_set_sail_button)
	_quit_button = Button.new()
	_quit_button.text = "退出"
	_quit_button.pressed.connect(_on_quit)
	box.add_child(_quit_button)

# 出航 → RouteScene（IDLE 自动起航）。经接缝避免测试真的切场景。
func _on_set_sail() -> void:
	_nav_set_sail.call()

# 退出 → 关闭游戏。经接缝避免测试退出运行器。
func _on_quit() -> void:
	_nav_quit.call()
