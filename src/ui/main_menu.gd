# 主菜单（启动场景）：奇幻英雄集结登录界面——冰原雪山背景 + 三英雄站位 +
# 船长代号/起航/游客模式 + 继续航程/设置/退出。视觉层缺美术素材时程序化占位。
# 导航/退出经可注入 Callable 接缝（DI over singleton），测试覆盖为 no-op。
class_name MainMenu
extends Control

const ART_DIR := "res://assets/art/menu/"
const ART_BG_FAR := ART_DIR + "bg_far.png"
const ART_BG_MID := ART_DIR + "bg_mid.png"
const ART_HERO_CENTER := ART_DIR + "hero_center.png"
const ART_HERO_LEFT := ART_DIR + "hero_left.png"
const ART_HERO_RIGHT := ART_DIR + "hero_right.png"

var _bg_far: TextureRect = null
var _bg_mid: TextureRect = null
var _hero_center: TextureRect = null
var _hero_left: TextureRect = null
var _hero_right: TextureRect = null
var _vignette: ColorRect = null

var _set_sail_button: Button = null
var _continue_button: Button = null            # 仅在存在进行中存档时创建
var _quit_button: Button = null
var _settings_button: Button = null
var _guest_button: Button = null
var _captain_input: LineEdit = null
var _captain_path: String = "user://captain.json"   # 测试可注入
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
	_build_background()
	_build_heroes()
	_build_vignette()
	_layout_heroes()
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.position.y -= 40   # 略离底边，避免遮挡英雄重点区
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
	_captain_input.text = load_captain()
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
	save_captain()
	_nav_set_sail.call()

# 继续航程 → 还原存档并回到 RouteScene。经接缝避免测试真的读盘/切场景。
func _on_continue() -> void:
	_nav_continue.call()

# 设置 → SettingsScreen。经接缝避免测试真的切场景。
func _on_settings() -> void:
	_nav_settings.call()

# 游客模式 → 直接进 RouteScene。经接缝避免测试真的切场景。
func _on_guest() -> void:
	save_captain()
	_nav_guest.call()

# 当前船长代号（去除首尾空白）。
func _captain_name() -> String:
	return _captain_input.text.strip_edges()

# 把当前船长代号写入本地 JSON（空名也安全）。仿 MetaProgress 持久化。
func save_captain() -> void:
	var f := FileAccess.open(_captain_path, FileAccess.WRITE)
	if f == null:
		push_error("MainMenu.save_captain: 无法写入 %s" % _captain_path)
		return
	f.store_string(JSON.stringify({"name": _captain_name()}))
	f.close()

# 读取上次船长代号；缺文件/坏文件 → 空串（不报错）。
func load_captain() -> String:
	if not FileAccess.file_exists(_captain_path):
		return ""
	var f := FileAccess.open(_captain_path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var d := parsed as Dictionary
		return str(d.get("name", ""))
	return ""

# 退出 → 关闭游戏。经接缝避免测试退出运行器。
func _on_quit() -> void:
	_nav_quit.call()

# ── 视觉层（缺美术素材时程序化占位）─────────────────────────────

# 资源存在则返回贴图，否则返回 null（缺图走占位）。
func _load_or_null(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res as Texture2D
	return null

# 冷色渐变占位贴图（背景缺图时用）。
func _cold_gradient() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.09, 0.16, 0.24))   # 上：深冷蓝
	grad.set_color(1, Color(0.55, 0.66, 0.74))   # 下：雪雾灰蓝
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 64
	tex.height = 64
	return tex

# 铺满背景的 TextureRect（缺图用冷色渐变占位）。
func _make_bg_layer(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.texture = tex if tex != null else _cold_gradient()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _build_background() -> void:
	_bg_far = _make_bg_layer(_load_or_null(ART_BG_FAR))
	add_child(_bg_far)
	_bg_mid = _make_bg_layer(_load_or_null(ART_BG_MID))
	if _load_or_null(ART_BG_MID) == null:
		_bg_mid.modulate = Color(1, 1, 1, 0.0)   # 缺中景图则透明（仅留远景占位）
	add_child(_bg_mid)

# 英雄槽：有图用 TextureRect，缺图用半透明占位贴图（由 modulate 上色）。
func _make_hero(tex: Texture2D, tint: Color) -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		r.texture = tex
	else:
		var ph := PlaceholderTexture2D.new()   # 缺图占位（透明灰块，由 modulate 上色）
		ph.size = Vector2(420, 760)
		r.texture = ph
		r.modulate = tint
	return r

func _build_heroes() -> void:
	# 左·绿色远程、右·蓝色奥术、中央·暖色主英雄（更大、最后加=最上）
	_hero_left = _make_hero(_load_or_null(ART_HERO_LEFT), Color(0.45, 0.8, 0.4, 0.85))
	_hero_left.custom_minimum_size = Vector2(360, 640)
	add_child(_hero_left)
	_hero_right = _make_hero(_load_or_null(ART_HERO_RIGHT), Color(0.4, 0.6, 0.95, 0.85))
	_hero_right.custom_minimum_size = Vector2(360, 640)
	add_child(_hero_right)
	_hero_center = _make_hero(_load_or_null(ART_HERO_CENTER), Color(1.0, 0.7, 0.35, 0.95))
	_hero_center.custom_minimum_size = Vector2(520, 880)
	add_child(_hero_center)

# 暗角叠层（半透明边框暗化占位；Task4 可换径向着色器）。
func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.02, 0.04, 0.07, 0.28)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)

# 按视口尺寸摆放英雄（中央居中略上，左右分居两侧）。Task6 做窄屏收拢。
func _layout_heroes() -> void:
	var vp := get_viewport_rect().size
	if _hero_center != null:
		_hero_center.position = Vector2(vp.x * 0.5 - 260, vp.y * 0.30)
	if _hero_left != null:
		_hero_left.position = Vector2(vp.x * 0.18 - 180, vp.y * 0.36)
	if _hero_right != null:
		_hero_right.position = Vector2(vp.x * 0.82 - 180, vp.y * 0.34)
