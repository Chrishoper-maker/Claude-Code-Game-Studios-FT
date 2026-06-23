# 主菜单（启动场景，白盒 Control）。标题 + 悬赏解锁进度 + 出航 + 退出。
# 导航/退出经可注入 Callable 接缝（DI over singleton），测试覆盖为 no-op。
class_name MainMenu
extends Control

var _set_sail_button: Button = null
var _continue_button: Button = null            # 仅在存在进行中存档时创建
var _quit_button: Button = null
var _settings_button: Button = null
var _guest_button: Button = null
var _captain_input: LineEdit = null
var _unlock_label: Label = null

var _nav_set_sail: Callable
var _nav_continue: Callable
var _nav_quit: Callable
var _nav_settings: Callable
var _nav_guest: Callable
func _default_set_sail() -> void: SceneManager.goto_route()
func _default_continue() -> void:
	RunManager.load_run()        # 还原进行中 run（停在 DEPLOYING/RECRUITING 航点）
	SceneManager.goto_route()    # RouteScene._ready 按 current_phase 渲染对应界面
func _default_quit() -> void: get_tree().quit()
func _default_settings() -> void: SceneManager.goto_settings()
func _default_guest() -> void: SceneManager.goto_route()   # 游客模式=跳过命名直接起航

func _ready() -> void:
	_nav_set_sail = _default_set_sail
	_nav_continue = _default_continue
	_nav_quit = _default_quit
	_nav_settings = _default_settings
	_nav_guest = _default_guest
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER)
	var title := Label.new()
	title.text = "《孤帆棋海》"
	box.add_child(title)
	_unlock_label = Label.new()
	_unlock_label.text = "悬赏解锁 %d / %d" % [MetaProgress.unlocked_crew_ids.size(), MetaProgress.get_unlock_order().size()]
	box.add_child(_unlock_label)
	# 有进行中存档时，"继续航程"置于"出航"之上。
	if RunManager.has_save():
		_continue_button = Button.new()
		_continue_button.text = "继续航程"
		_continue_button.pressed.connect(_on_continue)
		box.add_child(_continue_button)
	_captain_input = LineEdit.new()
	_captain_input.placeholder_text = "输入船长代号"
	box.add_child(_captain_input)
	_set_sail_button = Button.new()
	_set_sail_button.text = "起航"
	_set_sail_button.pressed.connect(_on_set_sail)
	box.add_child(_set_sail_button)
	_guest_button = Button.new()
	_guest_button.text = "游客模式"
	_guest_button.pressed.connect(_on_guest)
	box.add_child(_guest_button)
	_settings_button = Button.new()
	_settings_button.text = "设置"
	_settings_button.pressed.connect(_on_settings)
	box.add_child(_settings_button)
	_quit_button = Button.new()
	_quit_button.text = "退出"
	_quit_button.pressed.connect(_on_quit)
	box.add_child(_quit_button)

# 出航 → RouteScene（IDLE 自动起航；start_run 自动存档会覆盖旧存档）。经接缝避免测试真的切场景。
func _on_set_sail() -> void:
	_nav_set_sail.call()

# 继续航程 → 还原存档并回到 RouteScene。经接缝避免测试真的读盘/切场景。
func _on_continue() -> void:
	_nav_continue.call()

# 设置 → SettingsScreen。经接缝避免测试真的切场景。
func _on_settings() -> void:
	_nav_settings.call()

# 游客模式 → 直接进 RouteScene。经接缝避免测试真的切场景。
func _on_guest() -> void:
	_nav_guest.call()

# 当前船长代号（去除首尾空白）。
func _captain_name() -> String:
	return _captain_input.text.strip_edges()

# 退出 → 关闭游戏。经接缝避免测试退出运行器。
func _on_quit() -> void:
	_nav_quit.call()
