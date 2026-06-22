# 设置系统（MVP·主音量 + 显示模式）设计

> Story: settings-menu (#17) · 2026-06-23 · 引擎 Godot 4.6.3 / GDScript / GdUnit4

## 1. Overview

从主菜单进入的白盒设置界面，提供两项最基础设置——**主音量**与**显示模式
（窗口/全屏）**——并持久化到 `user://settings.json`，游戏启动时自动应用。
本期纯逻辑/白盒，无需任何美术或音频资源（主音量控制引擎 Master 总线，即使当前
无任何音效也是有效的基础设施，未来加入音乐/音效即自动受控）。

## 2. Player Fantasy

玩家能立刻调整最影响体验的两件事——声音大小与全屏与否——并且下次启动游戏时
设置被记住，不必每次重设。

## 3. Detailed Rules

### Rule 1 — SettingsManager（autoload，持久化 + 应用）
- `SettingsManager`（autoload，**不声明 class_name**，仿 MetaProgress 持久化模式）。
- 字段：
  - `master_volume: float = 1.0`（线性 0.0–1.0）。
  - `fullscreen: bool = false`。
  - `_save_path: String = "user://settings.json"`（测试可注入临时路径）。
- `_ready()`：`load_settings()` 然后 `apply_all()`。
- `set_master_volume(v: float) -> void`：`master_volume = clampf(v, 0.0, 1.0)` → `_apply_volume()` → `save_settings()`。
- `set_fullscreen(on: bool) -> void`：`fullscreen = on` → `_apply_window_mode()` → `save_settings()`。
- `_apply_volume() -> void`：
  - `AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))`（Master 总线 = index 0，恒存在）。
  - `AudioServer.set_bus_mute(0, master_volume <= 0.0)`（音量 0 → 静音，规避 `linear_to_db(0)= -inf`）。
- `_apply_window_mode() -> void`：`DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)`。
- `apply_all() -> void`：`_apply_volume()` + `_apply_window_mode()`。
- `to_dict() -> Dictionary`：`{"master_volume": master_volume, "fullscreen": fullscreen}`。
- `from_dict(d: Dictionary) -> void`：`master_volume = clampf(float(d.get("master_volume", 1.0)), 0.0, 1.0)`；`fullscreen = bool(d.get("fullscreen", false))`。
- `save_settings()` / `load_settings()`：JSON 读写 `_save_path`，缺文件 → 保持默认；坏文件（解析失败/非 Dictionary）→ `push_error` + 默认值。仿 MetaProgress.save_progress/load_progress。
- 注册进 `project.godot [autoload]`，置于 SceneManager 之前（SceneManager 须最后，ADR-0002）。

### Rule 2 — SettingsScreen（白盒界面）
- `src/ui/settings_screen.gd`（`class_name SettingsScreen extends Control`）+ `scenes/SettingsScreen.tscn`（Control 根 + 脚本，仿 MainMenu.tscn）。
- 程序化构建（仿 MainMenu `_ready`）：
  - 标题 Label「设置」。
  - 主音量：Label `_volume_label`（文案 `"主音量：%d%%" % round(master_volume*100)`）+ 「－」按钮 `_vol_down_button` + 「＋」按钮 `_vol_up_button`，每次 ±10%（步长 0.1），调用 `SettingsManager.set_master_volume(clampf(master_volume±0.1, 0, 1))` 后刷新标签。
  - 显示模式：按钮 `_window_button`，文案 `"显示模式：全屏" if fullscreen else "显示模式：窗口"`，点击 `SettingsManager.set_fullscreen(not fullscreen)` 后刷新文案。
  - 「返回」按钮 `_back_button` → `_nav_back` 接缝。
- 导航接缝（DI over singleton，仿 MainMenu）：`_nav_back: Callable`，默认 `_default_back()` 调 `SceneManager.goto_main_menu()`；测试覆盖 no-op。
- `_refresh()` 统一根据 SettingsManager 当前值刷新音量标签与显示模式按钮文案。

### Rule 3 — SceneManager 导航
- 新增 preload：`MAIN_MENU_SCENE := preload("res://scenes/MainMenu.tscn")`、`SETTINGS_SCENE := preload("res://scenes/SettingsScreen.tscn")`。
- 新增 `goto_settings() -> void`：`get_tree().change_scene_to_packed(SETTINGS_SCENE)`。
- 新增 `goto_main_menu() -> void`：`get_tree().change_scene_to_packed(MAIN_MENU_SCENE)`。
- SceneManager 仍为最后一个 autoload（ADR-0002 不变）。

### Rule 4 — MainMenu 设置入口
- `src/ui/main_menu.gd` 在「退出」按钮之前加「设置」按钮 `_settings_button`，`pressed` → `_on_settings()` → `_nav_settings.call()`。
- 新接缝 `_nav_settings: Callable`，默认 `_default_settings()` 调 `SceneManager.goto_settings()`；测试覆盖 no-op。

## 4. Formulas

- 线性音量 → 分贝：`db = linear_to_db(master_volume)`（master_volume>0）；master_volume≤0 时改用静音而非 -inf dB。
- 音量步进：`set_master_volume(clampf(master_volume + step, 0.0, 1.0))`，step = ±0.1。
- 百分比显示：`round(master_volume * 100)`。

## 5. Edge Cases

- **缺 settings.json**：`load_settings` 保持默认（1.0 / 窗口）。
- **坏 settings.json**（解析失败 / 非 Dictionary）：`push_error` + 默认值。
- **音量越界**：`clampf` 钳 0.0–1.0（步进到 0 或 1 后再点不越界）。
- **音量 0**：静音 Master 总线（`set_bus_mute(0, true)`），避免 `linear_to_db(0)` 的 -inf。
- **headless**：`DisplayServer.window_set_mode` 在 headless 驱动下安全（no-op 不崩）；`AudioServer` 总线 0 恒存在，`set_bus_volume_db/set_bus_mute` 安全。
- **from_dict 缺键**：逐键 `d.get(key, 默认)`，部分字典也安全。

## 6. Dependencies

- `AudioServer`（引擎内置，Master 总线 index 0）。
- `DisplayServer`（引擎内置，window_set_mode）。
- `SceneManager`（既有，加两个 goto 方法）。
- `MainMenu`（既有，加设置入口）。
- 无新增第三方库；无美术/音频资源。

## 7. Tuning Knobs

- 音量步长（当前 0.1 = 10%）。
- 默认值（master_volume 1.0 / fullscreen false）。
- 显示模式枚举（当前 WINDOWED / FULLSCREEN；可改 EXCLUSIVE_FULLSCREEN）。

## 8. Acceptance Criteria

- **AC-1**：`set_master_volume(0.5)` 后 `master_volume == 0.5`；`set_master_volume(2.0)` 钳为 1.0；`set_master_volume(-1.0)` 钳为 0.0。
- **AC-2**：`set_master_volume(0.0)` 后 `AudioServer.is_bus_mute(0)` 为真；`set_master_volume(0.5)` 后为假。
- **AC-3**：to_dict → from_dict 往返恢复 master_volume 与 fullscreen。
- **AC-4**：save_settings → load_settings 文件往返恢复设置；缺文件 load 后为默认；坏文件 load 后为默认。
- **AC-5**：SettingsScreen「＋」按钮调用后 master_volume 增加 0.1（上限钳 1.0）且音量标签更新；「－」对称；显示模式按钮切换 `fullscreen` 并更新按钮文案。
- **AC-6**：SettingsScreen「返回」触发 `_nav_back` 接缝。
- **AC-7**：MainMenu 含「设置」按钮，点击触发 `_nav_settings` 接缝。
- **AC-8**：全量回归绿、`--headless --import` 零错、零孤儿。

## 9. 非目标（YAGNI）

- 音乐 / 音效资源本身（本期只接通 Master 总线音量基础设施）。
- 分类音量（音乐 / 音效 / 语音独立总线）。
- 画质 / 分辨率 / 帧率 / 语言 / 键位重绑定设置。
- 滑动条控件（白盒用 ±按钮即可，符合"只用选项不打字"）。
- 设置项跨设备同步 / 云存档。
