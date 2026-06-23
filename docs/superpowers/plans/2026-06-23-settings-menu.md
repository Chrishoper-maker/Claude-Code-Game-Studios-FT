# 设置系统（MVP·主音量 + 显示模式）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从主菜单进入的白盒设置界面，控制主音量与显示模式（窗口/全屏），持久化到 `user://settings.json` 并在启动时应用。

**Architecture:** 新增 `SettingsManager` autoload（仿 MetaProgress 持久化模式，启动 load+apply，改动即存）+ 白盒 `SettingsScreen`（场景+脚本，经 `_nav_back` 接缝返回）+ SceneManager 加 `goto_settings/goto_main_menu` + MainMenu 加「设置」入口（`_nav_settings` 接缝）。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。

## Global Constraints

- 引擎 Godot 4.6.3；测试前必 `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import`；GdUnit4 须加 `--ignoreHeadlessMode`。
- 静态类型纪律：禁 `var x := <Variant 表达式>`；`Dictionary.get(...)` 结果用 `var x: Variant` + 类型守卫或显式转换。
- autoload 脚本**不声明 class_name**；Resource/UI 运行时类（SettingsScreen）**可**声明 class_name。
- 持久化：`user://settings.json`，路径 `_save_path` 可注入；缺文件/坏文件 → 默认值（master_volume=1.0 / fullscreen=false）。
- Master 总线 = AudioServer index 0（恒存在）；音量 0 用 `set_bus_mute(0,true)` 规避 `linear_to_db(0)=-inf`。
- SceneManager 必须是最后一个 autoload（ADR-0002）；SettingsManager 插在 RunManager 之后、SceneManager 之前。
- 驱 SettingsManager 的测试 `before_test` 重定向 `_save_path` 到临时文件并把 master_volume/fullscreen 复位默认；`after_test` 清理临时文件、复位、恢复 `_save_path`、`AudioServer.set_bus_mute(0,false)`。
- 中文对话；标识符英文。trunk-based 在 main。
- 提交 Conventional Commits，body 带 `Story: settings-menu (#17)`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。

---

### Task 1: SettingsManager autoload（持久化 + 应用）

**Files:**
- Create: `src/autoloads/settings_manager.gd`
- Modify: `project.godot`（`[autoload]` 段，RunManager 行后、SceneManager 行前插入 SettingsManager）
- Test: `tests/unit/settings/settings_manager_test.gd`

**Interfaces:**
- Produces：`SettingsManager.master_volume: float`、`fullscreen: bool`、`_save_path: String`；`set_master_volume(v: float)`、`set_fullscreen(on: bool)`、`apply_all()`、`to_dict() -> Dictionary`、`from_dict(d: Dictionary)`、`save_settings()`、`load_settings()`。

- [ ] **Step 1: 写脚本 SettingsManager**

`src/autoloads/settings_manager.gd`:

```gdscript
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
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))
	AudioServer.set_bus_mute(0, master_volume <= 0.0)   # 0 音量 → 静音，规避 -inf dB

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
```

- [ ] **Step 2: 注册 autoload**

`project.godot` `[autoload]` 段，在 `RunManager="*res://src/autoloads/run_manager.gd"` 行后插入：

```
SettingsManager="*res://src/autoloads/settings_manager.gd"
```

（确认 `SceneManager=...` 仍是该段最后一行。）

- [ ] **Step 3: 写失败测试**

`tests/unit/settings/settings_manager_test.gd`:

```gdscript
# SettingsManager：音量钳/静音、字典与文件往返、缺/坏文件默认。
extends GdUnitTestSuite

const TMP := "user://test_settings_mgr.json"

func before_test() -> void:
	SettingsManager._save_path = TMP
	SettingsManager.master_volume = 1.0
	SettingsManager.fullscreen = false
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

func after_test() -> void:
	SettingsManager.master_volume = 1.0
	SettingsManager.fullscreen = false
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)
	SettingsManager._save_path = "user://settings.json"
	AudioServer.set_bus_mute(0, false)

# AC-1：音量钳 0–1。
func test_set_master_volume_clamps() -> void:
	SettingsManager.set_master_volume(0.5)
	assert_float(SettingsManager.master_volume).is_equal_approx(0.5, 0.0001)
	SettingsManager.set_master_volume(2.0)
	assert_float(SettingsManager.master_volume).is_equal_approx(1.0, 0.0001)
	SettingsManager.set_master_volume(-1.0)
	assert_float(SettingsManager.master_volume).is_equal_approx(0.0, 0.0001)

# AC-2：0 音量静音 Master，非 0 解除。
func test_zero_volume_mutes_master() -> void:
	SettingsManager.set_master_volume(0.0)
	assert_bool(AudioServer.is_bus_mute(0)).is_true()
	SettingsManager.set_master_volume(0.5)
	assert_bool(AudioServer.is_bus_mute(0)).is_false()

# AC-3：to_dict → from_dict 往返。
func test_to_from_dict_roundtrip() -> void:
	SettingsManager.master_volume = 0.3
	SettingsManager.fullscreen = true
	var d := SettingsManager.to_dict()
	SettingsManager.master_volume = 1.0
	SettingsManager.fullscreen = false
	SettingsManager.from_dict(d)
	assert_float(SettingsManager.master_volume).is_equal_approx(0.3, 0.0001)
	assert_bool(SettingsManager.fullscreen).is_true()

# AC-4：save → load 文件往返。
func test_save_load_roundtrip() -> void:
	SettingsManager.set_master_volume(0.7)
	SettingsManager.set_fullscreen(true)
	SettingsManager.master_volume = 1.0
	SettingsManager.fullscreen = false
	SettingsManager.load_settings()
	assert_float(SettingsManager.master_volume).is_equal_approx(0.7, 0.0001)
	assert_bool(SettingsManager.fullscreen).is_true()

# AC-4：缺文件 load → 默认。
func test_load_missing_file_defaults() -> void:
	SettingsManager.master_volume = 0.42
	SettingsManager.load_settings()   # TMP 已在 before_test 删除
	assert_float(SettingsManager.master_volume).is_equal_approx(1.0, 0.0001)

# AC-4：坏文件 load → 默认。
func test_load_corrupt_file_defaults() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("}{ not json")
	f.close()
	SettingsManager.master_volume = 0.42
	SettingsManager.load_settings()
	assert_float(SettingsManager.master_volume).is_equal_approx(1.0, 0.0001)
```

- [ ] **Step 4: 导入 + 跑测试（RED→GREEN）**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/settings/settings_manager_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
```
Expected: 写脚本+注册后 6/6 PASSED（先确认 RED：未建脚本时 autoload 注册会报错，故 Step 1-2 与测试同批；RED 体现为 SettingsManager 方法不存在时运行错误）。

- [ ] **Step 5: 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: 全量绿、0 错误（新增 autoload 启动 apply_all 在 headless 安全）。

- [ ] **Step 6: 提交**

```bash
git add src/autoloads/settings_manager.gd project.godot tests/unit/settings/
git commit -F - <<'EOF'
feat(settings): SettingsManager autoload — master volume + display mode persistence

Story: settings-menu (#17)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

> 注：新 `.gd`/测试目录生成 `.uid` 边车，`git add` 目录已含；提交前 `git status` 确认无遗漏。

---

### Task 2: SettingsScreen 白盒界面 + SceneManager 导航

**Files:**
- Create: `src/ui/settings_screen.gd`、`scenes/SettingsScreen.tscn`
- Modify: `src/autoloads/scene_manager.gd`
- Test: `tests/integration/settings_screen/settings_screen_test.gd`

**Interfaces:**
- Consumes：`SettingsManager.master_volume/fullscreen/set_master_volume/set_fullscreen`（Task 1）、`SceneManager.goto_main_menu()`（本任务新增）。
- Produces：`SettingsScreen`（class_name）字段 `_volume_label/_window_button/_vol_down_button/_vol_up_button/_back_button`、接缝 `_nav_back`、处理器 `_on_vol_up/_on_vol_down/_on_window_toggle/_on_back`、`_refresh()`；`SceneManager.SETTINGS_SCENE/MAIN_MENU_SCENE` 常量、`goto_settings()/goto_main_menu()`。

- [ ] **Step 1: 写脚本 SettingsScreen**

`src/ui/settings_screen.gd`:

```gdscript
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
```

- [ ] **Step 2: 写场景 SettingsScreen.tscn**

`scenes/SettingsScreen.tscn`（仿 MainMenu.tscn）:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/settings_screen.gd" id="1"]

[node name="SettingsScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")
```

- [ ] **Step 3: SceneManager 加导航（场景先建好再 preload）**

`src/autoloads/scene_manager.gd`，在现有 `const ROUTE_SCENE := ...` 行后加：

```gdscript
const MAIN_MENU_SCENE := preload("res://scenes/MainMenu.tscn")
const SETTINGS_SCENE := preload("res://scenes/SettingsScreen.tscn")
```

在 `goto_route()` 方法之后加：

```gdscript
func goto_settings() -> void:
	get_tree().change_scene_to_packed(SETTINGS_SCENE)

func goto_main_menu() -> void:
	get_tree().change_scene_to_packed(MAIN_MENU_SCENE)
```

- [ ] **Step 4: 写失败测试**

`tests/integration/settings_screen/settings_screen_test.gd`:

```gdscript
# SettingsScreen 白盒交互：音量 ±、显示模式切换、返回接缝、场景实例化。
extends GdUnitTestSuite

const TMP := "user://test_settings_screen.json"

func before_test() -> void:
	SettingsManager._save_path = TMP
	SettingsManager.master_volume = 1.0
	SettingsManager.fullscreen = false
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

func after_test() -> void:
	SettingsManager.master_volume = 1.0
	SettingsManager.fullscreen = false
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)
	SettingsManager._save_path = "user://settings.json"
	AudioServer.set_bus_mute(0, false)

# AC-5：＋ 升 0.1 并更新标签。
func test_volume_up_increases_and_labels() -> void:
	SettingsManager.master_volume = 0.5
	var s: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(s)
	s._on_vol_up()
	assert_float(SettingsManager.master_volume).is_equal_approx(0.6, 0.0001)
	assert_str(s._volume_label.text).contains("60")

# AC-5：＋ 上限钳 1.0。
func test_volume_up_clamps_at_one() -> void:
	SettingsManager.master_volume = 1.0
	var s: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(s)
	s._on_vol_up()
	assert_float(SettingsManager.master_volume).is_equal_approx(1.0, 0.0001)

# AC-5：－ 降 0.1。
func test_volume_down_decreases() -> void:
	SettingsManager.master_volume = 0.5
	var s: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(s)
	s._on_vol_down()
	assert_float(SettingsManager.master_volume).is_equal_approx(0.4, 0.0001)

# AC-5：显示模式切换 + 按钮文案。
func test_window_toggle_flips_and_labels() -> void:
	SettingsManager.fullscreen = false
	var s: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(s)
	s._on_window_toggle()
	assert_bool(SettingsManager.fullscreen).is_true()
	assert_str(s._window_button.text).contains("全屏")

# AC-6：返回触发接缝。
func test_back_invokes_nav_seam() -> void:
	var s: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(s)
	var called := [0]
	s._nav_back = func() -> void: called[0] += 1
	s._on_back()
	assert_int(called[0]).is_equal(1)

# 场景实例化 smoke（SceneManager preload 正确）。
func test_scenes_instantiate() -> void:
	var ss: Node = SceneManager.SETTINGS_SCENE.instantiate()
	assert_bool(ss is SettingsScreen).is_true()
	ss.free()
	var mm: Node = SceneManager.MAIN_MENU_SCENE.instantiate()
	assert_bool(mm is MainMenu).is_true()
	mm.free()
```

- [ ] **Step 5: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/settings_screen/settings_screen_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary" | tail -1
```
Expected: 6/6 PASSED；全量绿。

- [ ] **Step 6: 提交**

```bash
git add src/ui/settings_screen.gd scenes/SettingsScreen.tscn src/autoloads/scene_manager.gd tests/integration/settings_screen/
git commit -F - <<'EOF'
feat(ui): whitebox SettingsScreen + SceneManager settings/main-menu nav

Story: settings-menu (#17)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 3: MainMenu 设置入口

**Files:**
- Modify: `src/ui/main_menu.gd`
- Test: `tests/integration/main_menu/main_menu_test.gd`（追加 2 测试）

**Interfaces:**
- Consumes：`SceneManager.goto_settings()`（Task 2）。
- Produces：`MainMenu._settings_button`、`_nav_settings: Callable`、`_on_settings()`。

- [ ] **Step 1: 追加失败测试**

在 `tests/integration/main_menu/main_menu_test.gd` 末尾追加：

```gdscript
# AC-7：渲染「设置」按钮。
func test_renders_settings_button() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._settings_button != null).is_true()

# AC-7：设置触发导航接缝。
func test_settings_invokes_nav_seam() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	var called := [0]
	mm._nav_settings = func() -> void: called[0] += 1
	mm._on_settings()
	assert_int(called[0]).is_equal(1)
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/main_menu/main_menu_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -4
```
Expected: 运行错误（`_settings_button` / `_nav_settings` / `_on_settings` 不存在）。

- [ ] **Step 3: 加字段 + 接缝**

`src/ui/main_menu.gd`，在 `var _quit_button: Button = null` 行后加：

```gdscript
var _settings_button: Button = null
```

在 `var _nav_quit: Callable` 行后加：

```gdscript
var _nav_settings: Callable
```

在 `func _default_quit() -> void: get_tree().quit()` 行后加：

```gdscript
func _default_settings() -> void: SceneManager.goto_settings()
```

- [ ] **Step 4: _ready 赋接缝 + 建按钮**

`_ready()` 中 `_nav_quit = _default_quit` 行后加：

```gdscript
	_nav_settings = _default_settings
```

在创建「退出」按钮的 `_quit_button = Button.new()` 行之前插入「设置」按钮：

```gdscript
	_settings_button = Button.new()
	_settings_button.text = "设置"
	_settings_button.pressed.connect(_on_settings)
	box.add_child(_settings_button)
```

- [ ] **Step 5: 加处理器**

在 `func _on_quit() -> void:` 方法之前（或 `_on_set_sail` 之后）加：

```gdscript
# 设置 → SettingsScreen。经接缝避免测试真的切场景。
func _on_settings() -> void:
	_nav_settings.call()
```

- [ ] **Step 6: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/main_menu/main_menu_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|Executed test|SCRIPT ERROR" | tail -4
```
Expected: main_menu 全部 PASSED（原 8 + 新 2 = 10）；全量绿、0 错误/孤儿（AC-8）。

- [ ] **Step 7: 提交**

```bash
git add src/ui/main_menu.gd tests/integration/main_menu/main_menu_test.gd
git commit -F - <<'EOF'
feat(ui): main menu settings entry button

Story: settings-menu (#17)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**Spec coverage:**
- Rule 1 SettingsManager（字段/_ready load+apply/set_master_volume 钳+应用+存/set_fullscreen/apply_all/_apply_volume 含静音/_apply_window_mode/to_from_dict/save_load 缺坏默认/注册）→ Task 1 ✓
- Rule 2 SettingsScreen（场景+脚本/音量±标签/显示模式切换/返回接缝/_refresh）→ Task 2 ✓
- Rule 3 SceneManager（两 preload + goto_settings/goto_main_menu）→ Task 2 ✓
- Rule 4 MainMenu 设置入口（按钮 + _nav_settings 接缝 + _on_settings）→ Task 3 ✓
- 边界：缺/坏文件默认（Task1 测试）/音量钳（Task1）/音量0静音（Task1）/headless 安全（启动 apply_all + 全量回归）/from_dict 缺键（逐键 get 默认）✓
- AC-1..4 → Task 1；AC-5/6 → Task 2；AC-7 → Task 3；AC-8 全量回归 → 各任务 ✓

**Placeholder scan:** 无 TBD/TODO；每步完整代码/命令+期望。✓

**Type consistency:**
- `master_volume: float` / `fullscreen: bool` / `_save_path: String`、`set_master_volume(float)` / `set_fullscreen(bool)` / `to_dict()->Dictionary` / `from_dict(Dictionary)` 在 Task 1 定义，Task 2 SettingsScreen 与测试一致引用。
- `SceneManager.goto_main_menu()`（Task 2）被 SettingsScreen `_default_back` 调用；`goto_settings()`（Task 2）被 MainMenu `_default_settings`（Task 3）调用。
- `SETTINGS_SCENE/MAIN_MENU_SCENE` 常量（Task 2）被 Task 2 smoke 测试引用。
- `SettingsScreen` class_name（Task 2）被测试与 SceneManager smoke 断言 `is SettingsScreen`；`MainMenu` class_name 既有。
- 静态类型：`var parsed: Variant` + `is Dictionary` 守卫；`clampf/linear_to_db/int(round(...))`；测试 `Array[String]` 不涉及；`is_equal_approx(expected, 0.0001)`。✓
- DisplayServer 枚举 `WINDOW_MODE_FULLSCREEN/WINDOW_MODE_WINDOWED`（Godot 4.6 DisplayServer 常量）。✓
