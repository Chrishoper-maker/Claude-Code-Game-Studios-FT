# 主菜单·奇幻英雄集结改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把白盒主菜单改造成奇幻英雄集结风格游戏登录界面（冰原雪山背景、三英雄站位、冷暖光对比、视差/粒子/呼吸光/淡入/光扫/聚焦发光动效、船长代号输入 + 游客模式），保留全部现有逻辑与测试。

**Architecture:** 沿用项目"全部在 `_ready` 代码构建"的白盒惯例——视觉层（背景/英雄/雾/粒子/暗角）、交互控件（按钮/输入框）、动效全部由 `main_menu.gd` 代码建立，`MainMenu.tscn` 仍只是带脚本的 `Control` 根。逻辑层（DI 接缝/处理器/字段/10 个现有测试）原样保留，表现层与新登录交互叠加其上。美术用常量路径槽位，缺 PNG 时程序化占位，素材到位零代码替换。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4；`TextureRect`/`ColorRect`/`Polygon2D`/`GPUParticles2D`/`ShaderMaterial`(.gdshader)/`LineEdit`/`StyleBoxFlat`/`Tween`。

## Global Constraints

- 引擎 Godot 4.6.3；测试前必 `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import`；GdUnit4 须加 `--ignoreHeadlessMode`。
- Godot 二进制：`/Applications/Godot.app/Contents/MacOS/Godot`。
- 静态类型纪律：禁 `var x := <Variant 表达式>`；`Dictionary.get(...)` 结果用 `var x: Variant` + 类型守卫或显式转换。
- `MainMenu` 保留 `class_name MainMenu extends Control`。autoload 脚本不声明 class_name（本期不动 autoload）。
- 交互控件（按钮/输入框）继续在 `_ready` 代码创建并持有字段引用，保证 `MainMenu.new()`→`add_child`→断言字段非 null 的现有测试模式不破。
- 视觉/动效/粒子/着色器/响应式不做单测，F5 人眼验收（沿用 RouteScene/BattleScene 惯例）。
- 持久化（若做）沿用 JSON + `is Dictionary` 守卫 + 缺/坏文件优雅，路径字段可注入临时路径，测试 before/after 清理。
- headless 安全：`GPUParticles2D`/`ShaderMaterial`/`Tween`/`TextureRect`/`LineEdit` 构建在无头模式安全（不渲染）；`_ready` 启动动效在测试中无害。
- 中文注释；标识符英文。trunk-based 在 main。
- 提交 Conventional Commits，body 带 `Story: main-menu-fantasy-redesign (#18)`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 美术槽缺失 PNG 时必须回退程序化占位，绝不报错/空场景。

---

### Task 1: 登录交互核心（起航改名 + 船长代号输入 + 游客模式）

**Files:**
- Modify: `src/ui/main_menu.gd`
- Test: `tests/integration/main_menu/main_menu_test.gd`（追加测试）

**Interfaces:**
- Consumes：现有 `SceneManager.goto_route()`、`RunManager.has_save()`、`MetaProgress`。
- Produces：`MainMenu._captain_input: LineEdit`、`_guest_button: Button`、`_nav_guest: Callable`、`_default_guest()`、`_on_guest()`、`_captain_name() -> String`。"出航"按钮文案改为"起航"（字段名 `_set_sail_button`、接缝 `_nav_set_sail`、处理器 `_on_set_sail` 全部不变）。

- [ ] **Step 1: 追加失败测试**

在 `tests/integration/main_menu/main_menu_test.gd` 末尾追加：

```gdscript
# AC-5：渲染船长代号输入框。
func test_renders_captain_input() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._captain_input != null).is_true()

# AC-5：渲染「游客模式」按钮。
func test_renders_guest_button() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._guest_button != null).is_true()

# AC-5：游客模式触发导航接缝。
func test_guest_invokes_nav_seam() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	var called := [0]
	mm._nav_guest = func() -> void: called[0] += 1
	mm._on_guest()
	assert_int(called[0]).is_equal(1)

# AC-5：船长代号 getter 返回去空白后的输入文本。
func test_captain_name_returns_trimmed_text() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	mm._captain_input.text = "  红胡子  "
	assert_str(mm._captain_name()).is_equal("红胡子")
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/main_menu/main_menu_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -5
```
Expected: 运行错误/失败（`_captain_input`/`_guest_button`/`_nav_guest`/`_on_guest`/`_captain_name` 不存在）。

- [ ] **Step 3: 加字段（在现有按钮字段区）**

`src/ui/main_menu.gd`，在 `var _settings_button: Button = null` 行后加：

```gdscript
var _guest_button: Button = null
var _captain_input: LineEdit = null
```

- [ ] **Step 4: 加游客接缝（在现有接缝区）**

在 `var _nav_settings: Callable` 行后加：

```gdscript
var _nav_guest: Callable
```

在 `func _default_settings() -> void: SceneManager.goto_settings()` 行后加：

```gdscript
func _default_guest() -> void: SceneManager.goto_route()   # 游客模式=跳过命名直接起航
```

- [ ] **Step 5: `_ready` 赋游客接缝 + 建输入框/游客按钮 + 起航改名**

在 `_ready()` 中 `_nav_settings = _default_settings` 行后加：

```gdscript
	_nav_guest = _default_guest
```

把建"出航"按钮处文案改名（`_set_sail_button.text` 由 `"出航"` 改为 `"起航"`）：

```gdscript
	_set_sail_button = Button.new()
	_set_sail_button.text = "起航"
	_set_sail_button.pressed.connect(_on_set_sail)
	box.add_child(_set_sail_button)
```

在 `_set_sail_button` 之前插入船长代号输入框（置于起航之上）：

```gdscript
	_captain_input = LineEdit.new()
	_captain_input.placeholder_text = "输入船长代号"
	box.add_child(_captain_input)
```

在 `_set_sail_button` 之后、`_settings_button` 之前插入游客按钮：

```gdscript
	_guest_button = Button.new()
	_guest_button.text = "游客模式"
	_guest_button.pressed.connect(_on_guest)
	box.add_child(_guest_button)
```

- [ ] **Step 6: 加 `_on_guest` 处理器 + `_captain_name` getter**

在 `func _on_settings()` 方法之后加：

```gdscript
# 游客模式 → 直接进 RouteScene。经接缝避免测试真的切场景。
func _on_guest() -> void:
	_nav_guest.call()

# 当前船长代号（去除首尾空白）。
func _captain_name() -> String:
	return _captain_input.text.strip_edges()
```

- [ ] **Step 7: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/main_menu/main_menu_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: main_menu 全部 PASSED（原 10 + 新 4 = 14）；全量绿、0 错误。

- [ ] **Step 8: 提交**

```bash
git add src/ui/main_menu.gd tests/integration/main_menu/main_menu_test.gd
git commit -F - <<'EOF'
feat(menu): captain-code input + guest mode; rename 出航→起航

Story: main-menu-fantasy-redesign (#18)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 2: 船长代号本地存名（可注入路径，缺/坏文件优雅）

**Files:**
- Modify: `src/ui/main_menu.gd`
- Test: `tests/integration/main_menu/main_menu_test.gd`（追加测试）

**Interfaces:**
- Consumes：Task 1 的 `_captain_input`、`_captain_name()`、`_on_set_sail`、`_on_guest`。
- Produces：`MainMenu._captain_path: String`、`save_captain()`、`load_captain() -> String`。`_ready` 用 `load_captain()` 回填输入框；`_on_set_sail`/`_on_guest` 起航前 `save_captain()`。

- [ ] **Step 1: 追加失败测试**

在 `main_menu_test.gd` 顶部常量区（`const TMP_SAVE := ...` 行后）加：

```gdscript
const TMP_CAPTAIN := "user://test_main_menu_captain.json"
```

在 `before_test()` 末尾加：

```gdscript
	if FileAccess.file_exists(TMP_CAPTAIN):
		DirAccess.remove_absolute(TMP_CAPTAIN)
```

在 `after_test()` 末尾加：

```gdscript
	if FileAccess.file_exists(TMP_CAPTAIN):
		DirAccess.remove_absolute(TMP_CAPTAIN)
```

在文件末尾追加测试：

```gdscript
# AC-5：船长代号存盘往返（注入临时路径）。
func test_captain_save_load_roundtrip() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	mm._captain_path = TMP_CAPTAIN
	add_child(mm)
	mm._captain_input.text = "钢爪"
	mm.save_captain()
	assert_str(mm.load_captain()).is_equal("钢爪")

# AC-5：缺文件 load → 空串。
func test_captain_load_missing_returns_empty() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	mm._captain_path = TMP_CAPTAIN   # before_test 已删，保证不存在
	add_child(mm)
	assert_str(mm.load_captain()).is_equal("")

# AC-5：坏文件 load → 空串。
func test_captain_load_corrupt_returns_empty() -> void:
	var f := FileAccess.open(TMP_CAPTAIN, FileAccess.WRITE)
	f.store_string("}{ not json")
	f.close()
	var mm: MainMenu = auto_free(MainMenu.new())
	mm._captain_path = TMP_CAPTAIN
	add_child(mm)
	assert_str(mm.load_captain()).is_equal("")
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/main_menu/main_menu_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -5
```
Expected: 运行错误（`_captain_path`/`save_captain`/`load_captain` 不存在）。

- [ ] **Step 3: 加路径字段**

`src/ui/main_menu.gd`，在 `var _captain_input: LineEdit = null` 行后加：

```gdscript
var _captain_path: String = "user://captain.json"   # 测试可注入
```

- [ ] **Step 4: 加 save/load 方法**

在 `_captain_name()` 方法之后加：

```gdscript
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
```

- [ ] **Step 5: `_ready` 回填 + 起航/游客存名**

在 `_ready()` 中创建 `_captain_input` 之后加回填（缺存档则空串占位文本仍显示）：

```gdscript
	_captain_input.text = load_captain()
```

把 `_on_set_sail` 与 `_on_guest` 改为起航前存名：

```gdscript
func _on_set_sail() -> void:
	save_captain()
	_nav_set_sail.call()

func _on_guest() -> void:
	save_captain()
	_nav_guest.call()
```

> 注：Task 1 的 `test_set_sail_invokes_nav_seam`/`test_guest_invokes_nav_seam` 用默认 `_captain_path`（`user://captain.json`），`save_captain()` 会写真实文件。为避免污染，这两个测试**不注入路径但写入是无害幂等的**；若评审要求隔离，在这两测试里设 `mm._captain_path = TMP_CAPTAIN` 并依赖 before/after 清理（实现期按需加，推荐加以保持纯净）。

实现期请在 `test_set_sail_invokes_nav_seam`/`test_guest_invokes_nav_seam` 两测试的 `add_child(mm)` 之前加 `mm._captain_path = TMP_CAPTAIN`，保证不写真实 `user://captain.json`。

- [ ] **Step 6: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/main_menu/main_menu_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: main_menu 17/17 PASSED；全量绿、0 错误。

- [ ] **Step 7: 提交**

```bash
git add src/ui/main_menu.gd tests/integration/main_menu/main_menu_test.gd
git commit -F - <<'EOF'
feat(menu): persist captain code to local json (graceful missing/corrupt)

Story: main-menu-fantasy-redesign (#18)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 3: 美术槽位 + 程序化占位 + 分层背景/英雄/暗角

**Files:**
- Modify: `src/ui/main_menu.gd`
- Create: `assets/art/menu/.gdignore`（占位空目录用，避免空目录不入 git；实际 PNG 由用户后放）
- Test: `tests/integration/main_menu/main_menu_test.gd`（追加 smoke 测试）

**Interfaces:**
- Consumes：无（纯表现层 + 容错加载）。
- Produces：`MainMenu` 视觉字段 `_bg_far/_bg_mid: TextureRect`、`_hero_center/_hero_left/_hero_right: TextureRect`、`_vignette: ColorRect`；方法 `_build_background()`、`_build_heroes()`、`_apply_art()`、常量 `ART_DIR` 及各文件名常量。后续 Task 4/5/6 引用这些节点做动效/响应式。

**说明：** 视觉层在交互 UI（`box`）之前 `add_child`，使 UI 浮于视觉之上（Godot 兄弟节点后绘制者在上）。英雄居画面中上部、登录 `box` 锚定下方，避免遮挡（响应式细化在 Task 6）。

- [ ] **Step 1: 加视觉字段 + 常量**

`src/ui/main_menu.gd`，在 `class_name MainMenu extends Control` 行后、字段区顶部加：

```gdscript
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
```

- [ ] **Step 2: 写视觉构建方法**

在脚本末尾加（占位用 `GradientTexture2D` / `modulate` 冷暖区分；真图存在则覆盖 texture）：

```gdscript
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

# 英雄槽：有图用 TextureRect，缺图用半透明色块剪影占位。冷暖色由 modulate 区分。
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

# 径向暗角叠层（纯色 + 后续 Task4 可换着色器；此处先做简单半透明边框暗化占位）。
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
```

- [ ] **Step 3: `_ready` 头部装配视觉层（在建 `box` 之前）**

在 `_ready()` 最前面（`_nav_set_sail = _default_set_sail` 等接缝赋值之后、`var box := VBoxContainer.new()` 之前）加：

```gdscript
	_build_background()
	_build_heroes()
	_build_vignette()
	_layout_heroes()
```

并把登录 `box` 锚定到下方居中（替换原 `box.set_anchors_preset(Control.PRESET_CENTER)`）：

```gdscript
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.position.y -= 40   # 略离底边
```

- [ ] **Step 4: 创建美术目录占位**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
mkdir -p assets/art/menu
printf '' > assets/art/menu/.gdignore
```

（`.gdignore` 让 Godot 忽略空目录扫描；用户后放 PNG 时移除或保留均可。）

- [ ] **Step 5: 追加 smoke 测试（节点存在 + 缺图不崩）**

在 `main_menu_test.gd` 末尾追加：

```gdscript
# AC-1/2/3：视觉层节点在缺美术素材时仍由占位创建、不崩。
func test_visual_layers_present_with_placeholders() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._bg_far != null).is_true()
	assert_bool(mm._hero_center != null).is_true()
	assert_bool(mm._hero_left != null).is_true()
	assert_bool(mm._hero_right != null).is_true()
	assert_bool(mm._vignette != null).is_true()
```

- [ ] **Step 6: 导入 + 跑测试 + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/main_menu/main_menu_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: main_menu 18/18 PASSED；全量绿、0 错误。

- [ ] **Step 7: F5 人眼检查（记录，不阻断）**

打开 Godot 运行主场景，确认：三个英雄占位块按"中央大居中、左绿右蓝"分布、登录面板在下方不遮挡英雄、背景为冷色渐变。记录观察到报告。

- [ ] **Step 8: 提交**

```bash
git add src/ui/main_menu.gd assets/art/menu/.gdignore tests/integration/main_menu/main_menu_test.gd
git commit -F - <<'EOF'
feat(menu): layered background + hero slots with procedural placeholders

Story: main-menu-fantasy-redesign (#18)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 4: 氛围动效——视差漂移 + 雾着色器 + 风雪/能量粒子

**Files:**
- Modify: `src/ui/main_menu.gd`
- Create: `assets/shaders/menu_fog.gdshader`
- Test: 无新单测（视觉，F5）；保持全量绿。

**Interfaces:**
- Consumes：Task 3 的 `_bg_far`/`_bg_mid`。
- Produces：`MainMenu._fog: ColorRect`、`_snow: GPUParticles2D`、`_motes: GPUParticles2D`、`_parallax_t: float`；`_process(delta)` 视差漂移；常量 `MOUSE_PARALLAX := true`。

- [ ] **Step 1: 写雾着色器**

`assets/shaders/menu_fog.gdshader`:

```glsl
shader_type canvas_item;
// 缓慢横向滚动的低频噪声雾，冷白半透明叠加。
uniform float speed = 0.012;
uniform vec4 fog_color : source_color = vec4(0.75, 0.82, 0.88, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float a = hash(i), b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
void fragment() {
	vec2 uv = UV * vec2(3.0, 2.0);
	uv.x += TIME * speed * 6.0;
	float n = noise(uv) * 0.6 + noise(uv * 2.0) * 0.4;
	float a = smoothstep(0.35, 0.95, n) * 0.30;       // 雾浓度
	COLOR = vec4(fog_color.rgb, a);
}
```

- [ ] **Step 2: 雾层 + 粒子构建方法**

`src/ui/main_menu.gd` 末尾加：

```gdscript
func _build_fog() -> void:
	_fog = ColorRect.new()
	_fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/menu_fog.gdshader") as Shader
	_fog.material = mat
	add_child(_fog)   # 在英雄之前调用（见 Step3 顺序），雾位于背景与英雄之间

# 通用下落/上浮粒子。
func _make_particles(amount: int, color: Color, vy: float, spread_y: float) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = amount
	p.lifetime = 8.0
	p.preprocess = 4.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(get_viewport_rect().size.x * 0.6, 8.0, 1.0)
	pm.direction = Vector3(0, sign(vy), 0)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = absf(vy) * 0.6
	pm.initial_velocity_max = absf(vy)
	pm.scale_min = 0.5
	pm.scale_max = 1.8
	pm.color = color
	p.process_material = pm
	p.position = Vector2(get_viewport_rect().size.x * 0.5, spread_y)
	return p

func _build_particles() -> void:
	# 雪花：顶部下落，冷白
	_snow = _make_particles(120, Color(0.92, 0.96, 1.0, 0.8), 60.0, 0.0)
	add_child(_snow)
	# 能量微粒：底部上浮，冷蓝带暖点
	_motes = _make_particles(40, Color(0.5, 0.75, 1.0, 0.6), -28.0, get_viewport_rect().size.y)
	add_child(_motes)
```

加字段（字段区）：

```gdscript
const MOUSE_PARALLAX := true
var _fog: ColorRect = null
var _snow: GPUParticles2D = null
var _motes: GPUParticles2D = null
var _parallax_t: float = 0.0
```

- [ ] **Step 3: `_ready` 装配顺序（背景→雾→英雄→粒子→暗角）**

调整 `_ready` 视觉装配段为：

```gdscript
	_build_background()
	_build_fog()
	_build_heroes()
	_build_particles()
	_build_vignette()
	_layout_heroes()
```

- [ ] **Step 4: `_process` 视差漂移**

在脚本加：

```gdscript
func _process(delta: float) -> void:
	_parallax_t += delta
	var base_far := sin(_parallax_t * 0.15) * 12.0
	var base_mid := sin(_parallax_t * 0.15) * 24.0
	var mx := 0.0
	if MOUSE_PARALLAX:
		var vp := get_viewport_rect().size
		var m := get_viewport().get_mouse_position()
		mx = (m.x / maxf(vp.x, 1.0) - 0.5)   # -0.5..0.5
	if _bg_far != null:
		_bg_far.position.x = base_far + mx * 18.0
	if _bg_mid != null:
		_bg_mid.position.x = base_mid + mx * 36.0
```

- [ ] **Step 5: 导入 + 全量回归 + F5**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: 全量绿、0 错误（着色器/粒子 headless 安全）。F5：雾缓动、雪花飘落、能量上浮、背景轻微视差，无卡顿。

- [ ] **Step 6: 提交**

```bash
git add src/ui/main_menu.gd assets/shaders/menu_fog.gdshader
git commit -F - <<'EOF'
feat(menu): parallax drift + scrolling fog shader + snow/energy particles

Story: main-menu-fantasy-redesign (#18)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 5: UI 动效——面板淡入上移 + 武器呼吸 + 按钮光扫 + 输入框聚焦发光

**Files:**
- Modify: `src/ui/main_menu.gd`
- Create: `assets/shaders/button_sweep.gdshader`
- Test: 无新单测（视觉，F5）；保持全量绿。

**Interfaces:**
- Consumes：Task 1 的按钮/输入框字段、Task 3 的 `_hero_center`、登录 `box`。
- Produces：`MainMenu` 方法 `_animate_panel_in()`、`_animate_weapon_glow()`、`_style_buttons()`、`_attach_sweep(btn)`、`_attach_focus_glow(input)`；字段 `_panel_box: VBoxContainer`、`_weapon_glow: ColorRect`。

- [ ] **Step 1: 按钮光扫着色器**

`assets/shaders/button_sweep.gdshader`:

```glsl
shader_type canvas_item;
// 一条从左到右扫过的高光带，progress 由 0→1 时扫完。
uniform float progress = 0.0;   // 0..1；>1 表示不显示
uniform float band = 0.18;
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float d = abs(UV.x - progress);
	float hi = smoothstep(band, 0.0, d) * step(progress, 1.0);
	base.rgb += vec3(hi) * 0.5;
	COLOR = base;
}
```

- [ ] **Step 2: 持有 box 引用 + 武器光节点**

把 `_ready` 里 `var box := VBoxContainer.new()` 改为字段赋值，并加武器光字段。字段区加：

```gdscript
var _panel_box: VBoxContainer = null
var _weapon_glow: ColorRect = null
```

`_ready` 中 `var box := VBoxContainer.new()` 改为：

```gdscript
	_panel_box = VBoxContainer.new()
	var box := _panel_box
```

- [ ] **Step 3: 动效方法**

脚本末尾加：

```gdscript
# 面板淡入上移（进入动画）。
func _animate_panel_in() -> void:
	_panel_box.modulate.a = 0.0
	var start := _panel_box.position
	_panel_box.position = start + Vector2(0, 24)
	var t := create_tween().set_parallel(true)
	t.tween_property(_panel_box, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_panel_box, "position", start, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# 中央英雄武器暖色呼吸光（叠加 ColorRect + 循环 Tween）。
func _animate_weapon_glow() -> void:
	_weapon_glow = ColorRect.new()
	_weapon_glow.color = Color(1.0, 0.65, 0.25, 0.0)
	_weapon_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_glow.size = Vector2(260, 260)
	if _hero_center != null:
		_weapon_glow.position = _hero_center.position + Vector2(120, 380)
	add_child(_weapon_glow)
	var t := create_tween().set_loops()
	t.tween_property(_weapon_glow, "color:a", 0.35, 1.4).set_trans(Tween.TRANS_SINE)
	t.tween_property(_weapon_glow, "color:a", 0.08, 1.4).set_trans(Tween.TRANS_SINE)

# 给按钮挂 hover 光扫。
func _attach_sweep(btn: Button) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/button_sweep.gdshader") as Shader
	mat.set_shader_parameter("progress", 2.0)   # 初始不显示
	btn.material = mat
	btn.mouse_entered.connect(func() -> void:
		var t := create_tween()
		t.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.45)
		t.tween_callback(func() -> void: mat.set_shader_parameter("progress", 2.0))
	)

# 输入框聚焦边框发光。
func _attach_focus_glow(input: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.10, 0.16, 0.85)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.4, 0.55, 0.7, 0.8)
	normal.set_corner_radius_all(4)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.set_border_width_all(2)
	focus.border_color = Color(0.55, 0.85, 1.0, 1.0)
	input.add_theme_stylebox_override("normal", normal)
	input.add_theme_stylebox_override("focus", focus)

# 给所有菜单按钮统一暗底冷描边 + 光扫。
func _style_buttons() -> void:
	for b: Button in [_continue_button, _set_sail_button, _guest_button, _settings_button, _quit_button]:
		if b != null:
			_attach_sweep(b)
```

- [ ] **Step 4: `_ready` 末尾启动动效**

在 `_ready()` 末尾（建完所有按钮后）加：

```gdscript
	_style_buttons()
	_attach_focus_glow(_captain_input)
	_animate_weapon_glow()
	_animate_panel_in()
```

- [ ] **Step 5: 导入 + 全量回归 + F5**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: 全量绿、0 错误（Tween/ShaderMaterial/StyleBox headless 安全）。F5：面板淡入上移、武器暖光呼吸、按钮 hover 光扫一次、输入框聚焦边框变亮。

- [ ] **Step 6: 提交**

```bash
git add src/ui/main_menu.gd assets/shaders/button_sweep.gdshader
git commit -F - <<'EOF'
feat(menu): panel fade-in, weapon breathing glow, button hover sweep, input focus glow

Story: main-menu-fantasy-redesign (#18)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 6: 响应式 reflow（桌面/移动·窄屏自适应）

**Files:**
- Modify: `src/ui/main_menu.gd`
- Test: `tests/integration/main_menu/main_menu_test.gd`（追加纯函数测试）

**Interfaces:**
- Consumes：Task 3 的英雄节点/`_layout_heroes`、Task 5 的 `_weapon_glow`。
- Produces：`MainMenu._is_portrait(size: Vector2) -> bool`、`_relayout()`；`_ready` 连接 `get_viewport().size_changed`。

- [ ] **Step 1: 追加纯函数测试**

在 `main_menu_test.gd` 末尾追加：

```gdscript
# AC-6：竖/窄屏判定（高>宽 或 宽高比<1.2 视为窄）。
func test_is_portrait_detection() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._is_portrait(Vector2(1080, 1920))).is_true()
	assert_bool(mm._is_portrait(Vector2(1920, 1080))).is_false()
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/main_menu/main_menu_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -4
```
Expected: 运行错误（`_is_portrait` 不存在）。

- [ ] **Step 3: 加判定 + reflow**

脚本加：

```gdscript
# 窄/竖屏：宽高比 < 1.2 视为需收拢布局。
func _is_portrait(size: Vector2) -> bool:
	return size.x / maxf(size.y, 1.0) < 1.2

# 按当前视口重新摆放英雄与武器光（窄屏向中心收拢并缩小）。
func _relayout() -> void:
	var vp := get_viewport_rect().size
	var narrow := _is_portrait(vp)
	var spread := 0.18 if not narrow else 0.30   # 窄屏左右更靠中
	var hero_scale := 1.0 if not narrow else 0.7
	if _hero_center != null:
		_hero_center.scale = Vector2(hero_scale, hero_scale)
		_hero_center.position = Vector2(vp.x * 0.5 - 260 * hero_scale, vp.y * 0.30)
	if _hero_left != null:
		_hero_left.scale = Vector2(hero_scale, hero_scale)
		_hero_left.position = Vector2(vp.x * spread - 180 * hero_scale, vp.y * 0.36)
	if _hero_right != null:
		_hero_right.scale = Vector2(hero_scale, hero_scale)
		_hero_right.position = Vector2(vp.x * (1.0 - spread) - 180 * hero_scale, vp.y * 0.34)
	if _weapon_glow != null and _hero_center != null:
		_weapon_glow.position = _hero_center.position + Vector2(120, 380) * hero_scale
```

- [ ] **Step 4: `_ready` 连接 resize + 首次 reflow**

把 `_ready` 里的 `_layout_heroes()` 调用替换为 `_relayout()`，并在其后连接信号：

```gdscript
	_relayout()
	get_viewport().size_changed.connect(_relayout)
```

（`_layout_heroes` 可保留为内部初始定位或删除；若删除，确保无其他引用。推荐删除，逻辑并入 `_relayout`。）

- [ ] **Step 5: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/main_menu/main_menu_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: main_menu 19/19 PASSED；全量绿。F5：拖动窗口/切竖屏，英雄收拢缩放不裁切、面板不压角色。

- [ ] **Step 6: 提交**

```bash
git add src/ui/main_menu.gd tests/integration/main_menu/main_menu_test.gd
git commit -F - <<'EOF'
feat(menu): responsive reflow for narrow/portrait layouts

Story: main-menu-fantasy-redesign (#18)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 7: 集成收尾 + F5 验收 + 全量回归

**Files:**
- Modify: `src/ui/main_menu.gd`（仅按 F5 发现微调，如有）
- Test: 全量回归

**Interfaces:**
- Consumes：Task 1–6 全部。
- Produces：无新接口；F5 验收清单 + 全绿。

- [ ] **Step 1: 全量回归 + 导入零错/零孤儿**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|Executed test|SCRIPT ERROR|orphan" | tail -5
```
Expected: 全量绿、0 错误、0 孤儿。

- [ ] **Step 2: F5 验收清单（人眼，对照 spec §9 AC-1..8）**

逐项核对并记录：
- AC-1 启动即完整奇幻登录界面（背景+三英雄+登录面板）。
- AC-3 中央英雄更大居前、武器暖光；左绿右蓝。
- AC-4 视差/雪花/能量/呼吸光/面板淡入/按钮光扫/输入框聚焦发光齐全、不卡顿。
- AC-5 起航/游客模式/继续航程/设置/退出交互正常；起航与游客模式进入 RouteScene；船长代号回填。
- AC-6 桌面与窄屏布局自适应、文字不遮挡角色、英雄不裁切。
- AC-2 占位下呈现冷色冰原氛围（真实素材待用户 PNG）。

- [ ] **Step 3: （如有微调）提交**

```bash
git add -A
git commit -F - <<'EOF'
chore(menu): final integration polish for fantasy main menu

Story: main-menu-fantasy-redesign (#18)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

> 若 Step 1 全绿且 F5 无问题、无代码改动，则本任务无提交，仅记录 F5 验收结论。

---

## Self-Review

**Spec coverage（对照 spec §6 Rules / §9 AC）：**
- Rule 1 节点结构/保留逻辑层 → Task 1（逻辑）+ Task 3（视觉装配在 `box` 前）✓
- Rule 2 美术槽 + 占位回退 → Task 3（`_load_or_null`/占位）✓
- Rule 3 视差/微动 → Task 4（`_process` + 鼠标视差）✓
- Rule 4 粒子 → Task 4（snow/motes）✓
- Rule 5 武器呼吸 → Task 5（`_animate_weapon_glow`）✓
- Rule 6 登录面板（起航/游客/输入框/保留按钮）→ Task 1（控件+接缝）+ Task 3（面板下方锚定）✓
- Rule 7 船长存名（可选）→ Task 2 ✓
- Rule 8 动效（淡入/光扫/聚焦发光）→ Task 5 ✓
- Rule 9 响应式 → Task 6 ✓
- AC-1..8 → Task 7 F5 清单逐项覆盖；AC-5/7 逻辑层 Task 1/2/6 单测 ✓
- 原创性/Global Constraints → 全任务沿用占位+原创着色器，提交 body 带 Story ✓

**Placeholder scan：** 各步含完整代码/命令/期望；无 TBD/TODO；视觉任务以 import+全量绿+F5 清单替代单测（已显式说明）。✓

**Type consistency：**
- `_captain_input: LineEdit`/`_captain_name() -> String`/`_captain_path: String`/`save_captain()`/`load_captain() -> String`（Task 1/2）一致被 Task 2/5/6 引用。
- `_guest_button: Button`/`_nav_guest: Callable`/`_default_guest`/`_on_guest`（Task 1）。
- `_bg_far/_bg_mid/_hero_center/_hero_left/_hero_right: TextureRect`、`_vignette: ColorRect`（Task 3）被 Task 4/5/6 引用，类型一致。
- `_fog: ColorRect`/`_snow/_motes: GPUParticles2D`/`_parallax_t: float`（Task 4）。
- `_panel_box: VBoxContainer`/`_weapon_glow: ColorRect`（Task 5）被 Task 6 `_relayout` 引用。
- `_is_portrait(Vector2) -> bool`/`_relayout()`（Task 6）。
- `_load_or_null(String) -> Texture2D`、`_make_hero(Texture2D, Color) -> TextureRect`、`_make_bg_layer(Texture2D) -> TextureRect`（Task 3）签名一致。
- 静态类型：`var parsed: Variant` + `is Dictionary` 守卫（Task 2）；循环 `for b: Button in [...]`（Task 5）；`load(...) as Shader`/`as Texture2D` 显式转换。✓
