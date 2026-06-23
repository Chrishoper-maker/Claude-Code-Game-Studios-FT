# 主菜单·奇幻英雄集结改造 设计

> Story: main-menu-fantasy-redesign (#18) · 2026-06-23 · 引擎 Godot 4.6.3 / GDScript / GdUnit4

## 1. Overview

把现有纯白盒主菜单（`scenes/MainMenu.tscn` + `src/ui/main_menu.gd`）改造成
**奇幻英雄集结**风格的游戏登录界面：冰原雪山史诗背景、三名英雄站位（中央主英雄
突出、左右配角烘托）、冷色环境光与暖色武器光对比，外加视差、风雪粒子、呼吸发光、
面板淡入、按钮光扫、输入框聚焦发光等动效。新增"船长代号"输入框 + "游客模式"前端
登录交互。

**架构基线：保留逻辑层、叠加表现层。** 现 `main_menu.gd` 的 DI 接缝
（`_nav_set_sail/_nav_continue/_nav_quit/_nav_settings`）、处理器、交互控件字段
（`_set_sail_button/_continue_button/_settings_button/_quit_button/_unlock_label`）
**全部保留且行为不变**，现有 10 个 main_menu 测试保持绿。视觉与新登录交互在其上叠加。

**美术来源：** 玩家（用户）提供原创 PNG 立绘/背景素材。任一素材缺失时自动回退到
**程序化占位**（渐变/剪影），场景永不崩、可立即运行与测试，素材到位后零代码替换。

## 2. Player Fantasy

玩家一启动游戏，第一屏就是一幅史诗感的英雄集结画面——自己的船队三名英雄屹立在
风雪冰原上，中央船长的武器泛着暖光，背景是神秘远古遗迹。输入船长代号、点"起航"
即可开始航程，或"游客模式"一键进入。界面有呼吸感与微动，不是一张静止贴图。

## 3. Non-Goals（YAGNI）

- **无账号后端**：不做真实登录/注册/服务器校验。"登录"=前端交互态。
- **不做账号+密码完整登录面板**（已与用户确认采用"船长代号 + 游客模式"方案）。
- **不绑定玩法数据**：船长代号不影响任何战斗/run 逻辑，仅展示与本地存名。
- **不引入第三方美术/字体/IP 素材**：构图可借鉴通用范式，但不复制任何已有游戏角色/
  造型/Logo/素材。
- **不重写导航/run/settings 逻辑**：只改主菜单表现层 + 新增登录交互接缝。
- 视觉/动效**不做自动化单测**（沿用项目 RouteScene/BattleScene 等惯例，F5 人眼验收）。

## 4. 美术素材契约

原创 PNG 放 `assets/art/menu/`（用户提供）：

| 文件 | 内容 | 建议规格 |
|---|---|---|
| `bg_far.png` | 远山/雪山天际（最慢视差层） | ≥2400×1350，不透明 sRGB |
| `bg_mid.png` | 中景遗迹/神秘建筑轮廓 + 雾 | ≥2400×1350，透明 PNG |
| `hero_center.png` | 中央主英雄·重甲剑士船长（发光武器） | 透明，竖向 ~900×1300 |
| `hero_left.png` | 左·枪手/远程（绿色自然系） | 透明，~700×1100 |
| `hero_right.png` | 右·医疗/吟游（蓝色奥术·发光法杖） | 透明，~700×1100 |
| `weapon_glow.png`（可选） | 中央武器叠加暖光精灵 | 透明，加性混合用；缺则程序生成 |

- 雪花/能量粒子 = `GPUParticles2D` 程序生成，**无需素材**。
- **回退契约**：每个图槽对应一个常量路径；`_ready` 用 `ResourceLoader.exists(path)`
  判定，存在则 `load()` 贴图，缺失则用程序化占位（`GradientTexture2D` 背景 / 纯色
  `ColorRect` 剪影 + 冷暖 modulate）。缺素材绝不报错、绝不空场景。
- 素材文件由用户后续放入；本期实现用占位完成布局/动效/接线/测试。

## 5. 场景层次（从后到前，CanvasLayer/Control 树）

1. **视差背景层**：`bg_far`（漂移最慢）+ `bg_mid`（较快）；冷色环境光 `ColorRect`
   叠加（低 alpha 冷蓝）。
2. **雾气/风雪层**：滚动雾着色器（`ColorRect` + `.gdshader`，UV 随时间平移）+
   `GPUParticles2D` 雪花（自上而下缓慢飘落）。
3. **英雄层**：三个 `TextureRect`（或 `Sprite2D`）——中央更大、居前、居中；左右略小、
   略后、冷色 modulate 压暗。中央武器区叠加**暖色加性发光**（见 Rule §6 呼吸）。
4. **能量微粒层**：`GPUParticles2D`，冷色为主，中央附近少量暖色 motes。
5. **暗角 + 冷暖对比叠层**：`ColorRect` + 着色器（径向暗角 + 中央偏暖、边缘偏冷）。
6. **UI 登录面板层**（`CanvasLayer` 顶层，见 Rule §7）。

## 6. Detailed Rules

### Rule 1 — 节点结构与脚本组织
- `scenes/MainMenu.tscn` 重做为分层场景树（背景/雾/英雄/粒子/叠层/UI 面板各为命名
  节点），根仍为 `Control`，根脚本仍 `src/ui/main_menu.gd`（`class_name MainMenu`）。
- **交互控件（按钮/输入框）继续在 `_ready` 由代码创建并持有字段引用**，使现有
  DI 接缝 + 测试（`MainMenu.new()` → `add_child` → 断言字段非 null）不受 `.tscn`
  改动影响而保持绿。视觉装饰节点（背景/英雄/粒子/着色器）可在 `.tscn` 内预置，
  脚本用 `get_node_or_null` 取引用（缺失则容错）。
- 若 `main_menu.gd` 因表现层逻辑显著膨胀，拆出表现/动效辅助（如
  `src/ui/main_menu_visuals.gd` 或一个 `MenuFx` 节点脚本）承担纯视觉，主脚本只
  保留逻辑+接缝。具体拆分在 plan 阶段按体量决定，单文件单一职责。

### Rule 2 — 美术槽与占位回退
- 常量集中：`const ART_DIR := "res://assets/art/menu/"` + 各文件名常量。
- `_apply_art()`（`_ready` 调用）：对每个图槽，存在则赋 `texture`，缺失则装配
  程序化占位（背景=冷色 `GradientTexture2D`；英雄=半透明剪影 `ColorRect`/
  `Polygon2D`，中央暖描边、左绿右蓝 modulate）。
- 占位与真图**同一节点同一布局**，仅 `texture`/可见性差异，确保替换零回归。

### Rule 3 — 视差与微动
- `_process(delta)`：背景层按各自速度做缓慢水平自动漂移（循环/往复，幅度数像素~十
  几像素）。可选**轻微鼠标视差**：背景层依 `get_viewport().get_mouse_position()`
  归一化偏移做小幅 lerp（开关常量 `MOUSE_PARALLAX := true`）。
- 性能：纯 `Vector2` 位置写入，无每帧分配；视差幅度小，避免边缘露底（素材留边）。

### Rule 4 — 粒子（风雪 + 能量）
- 雪花：`GPUParticles2D`，发射区铺满顶部宽度，向下缓慢飘、轻微横摆，冷白色，
  半透明，循环。
- 能量微粒：第二个 `GPUParticles2D`，少量、上浮、冷蓝为主、中央附近暖橙点缀。
- 数量适中（数十~百级），保 60fps；`GPUParticles2D` 在 headless 安全（不渲染）。

### Rule 5 — 中央武器呼吸发光
- 中央英雄武器区叠加暖色加性发光（`weapon_glow.png` 或程序生成的暖色 `ColorRect`/
  `PointLight2D`/着色器）。
- `Tween`（`set_loops()`，往复）循环改其 `modulate.a` 或着色器强度参数，做缓慢
  呼吸（周期 ~2–3s）。

### Rule 6 — 登录面板（不遮挡英雄重点区）
- 面板锚定**下方居中**（英雄重点区在画面中上部，面板在下，验收"文字不遮挡角色
  重点区域"）。半透明深色底板 + 冷色描边。
- 内容（自上而下）：
  1. 标题《孤帆棋海》（奇幻风格标签，可加描边/暖色高亮）。
  2. 悬赏解锁进度 `_unlock_label`（**保留现有格式** `"悬赏解锁 %d / %d"`）。
  3. **船长代号输入框** `_captain_input: LineEdit`（占位文本"输入船长代号"；
     聚焦边框发光，见 Rule §8）。
  4. **主按钮"起航"** = 现 `_set_sail_button`（文本由"出航"改为"起航"），点击走
     `_on_set_sail` → `_nav_set_sail`（=`goto_route`，**接缝与行为不变**）。
  5. **"游客模式"按钮** `_guest_button`（新增）：点击 `_on_guest` → 新接缝
     `_nav_guest`，默认 `_default_guest`（=`SceneManager.goto_route()`，与起航同效，
     语义=跳过命名直接进）。
  6. 继续航程 `_continue_button`（**仅 `RunManager.has_save()` 为真时创建**，行为
     不变）/ 设置 `_settings_button` / 退出 `_quit_button`。
- 所有按钮/接缝/`_on_*` 处理器**保留现有名字与语义**；仅"出航"按钮文案改"起航"，
  新增 `_guest_button`/`_nav_guest`/`_default_guest`/`_on_guest`。

### Rule 7 — 船长代号本地存名（轻量、可注入、可缺省）
- `_captain_name() -> String`：返回输入框当前文本（trim）。
- 持久化：`user://captain.json`，`_captain_path: String`（测试可注入）。
  - `save_captain()`：把当前名写入 JSON `{"name": <str>}`；空名也安全写。
  - `load_captain() -> String`：缺文件/坏文件 → 返回 `""`（优雅，不报错），否则取
    `name` 字段。
  - `_ready`：`load_captain()` 回填输入框（上次代号）；起航/游客模式时 `save_captain()`。
- 仿 MetaProgress/SettingsManager 持久化风格（JSON、`is Dictionary` 守卫、
  `push_error` 仅用于真正异常）。**此 Rule 标为可选**：若实现期判定超预算可砍，
  仅保留输入框前端态（输入即用、不跨会话）。

### Rule 8 — 交互动效（表现层）
- **面板进入**：`_ready` 用 `Tween` 让面板 `modulate.a` 0→1 且 `position.y`
  +24→0（淡入上移，~0.4s，ease out）。
- **按钮 hover 光扫**：复用着色器（一条移动高光带），`mouse_entered` 触发一次扫过；
  封装为可复用函数/小节点，套用到全部菜单按钮。
- **输入框聚焦发光**：`_captain_input.focus_entered` → 边框发光（`StyleBoxFlat`
  发光描边 + `Tween` 脉冲），`focus_exited` 复原。
- **加载不卡顿**：素材异步无关（小图直接 load），动效用 Tween/着色器/GPUParticles，
  无每帧分配；目标 60fps。

### Rule 9 — 响应式（桌面 + 移动）
- `project.godot` 已 1920×1080 / `canvas_items` / `expand`，自动缩放。
- 锚点：背景铺满（`PRESET_FULL_RECT` + cover）；英雄居中带偏移；面板锚定下方居中。
- **窄/竖屏自适应**：监听 `get_viewport().size_changed`；当宽高比 < 阈值（竖屏/窄）
  时，左右英雄向中心收拢并缩放、面板继续下移堆叠，避免英雄被裁切、文字不压角色。

## 7. 数据流

启动 → `MainMenu._ready`：装配视觉层（`_apply_art` 占位/真图）→ 建交互控件（保留
字段+接缝）→ `load_captain` 回填 → 启动 Tween/粒子/视差。
玩家点"起航"→ `_on_set_sail` →（若做存名）`save_captain` → `_nav_set_sail`
（`goto_route`）。点"游客模式"→ `_on_guest` → `_nav_guest`（`goto_route`）。
其余按钮（继续航程/设置/退出）行为与现状完全一致。

## 8. 测试

- **现有 10 个 main_menu 测试保持绿**（交互控件仍代码建、接缝/处理器/字段不变；
  注意"出航"→"起航"文案若被某测试断言文本需同步——实现期核对）。
- 新增（白盒、DI 接缝模式）：
  - `_captain_input != null`（输入框已建）。
  - `_guest_button != null`（游客按钮已建）。
  - `_on_guest()` 触发 `_nav_guest` 接缝（no-op 计数）。
  - `_captain_name()` 返回输入框文本（设文本后断言）。
  - （若做存名）`save_captain`/`load_captain` 往返 + 缺/坏文件返回 `""`（注入临时
    `_captain_path`，before/after 清理）。
- 视觉/动效/粒子/着色器/响应式 = **不做单测**，F5 人眼验收（沿用项目惯例）。
- 全量套件保持绿、import 0 错误/0 孤儿。

## 9. Acceptance Criteria

- **AC-1**：启动即完整奇幻登录界面（非普通网页落地页），第一屏含背景+三英雄+登录面板。
- **AC-2**：背景为原创冰原/雪山/遗迹场景，含雾气、风雪、远山、神秘建筑轮廓（素材到位
  后；缺素材时程序化占位仍呈现冷色冰原氛围）。
- **AC-3**：中央主英雄体型更大、居前居中、武器/核心暖色发光；左=绿色远程、右=蓝色奥术。
- **AC-4**：动效齐备——背景缓慢视差、雪花/能量粒子漂浮、武器呼吸发光、面板淡入上移、
  按钮 hover 光扫、输入框聚焦发光；加载不卡顿（60fps 目标）。
- **AC-5**：船长代号输入框、起航、游客模式、继续航程/设置/退出交互均正常；起航/游客
  模式正确进入 RouteScene。
- **AC-6**：桌面端与移动/窄屏布局自适应，文字不遮挡角色重点区域，英雄不被裁切。
- **AC-7**：现有 10 个 main_menu 测试 + 新增测试全绿；全量套件绿、import 0 错误/孤儿。
- **AC-8**：所有交付视觉为原创（用户 PNG + 原创占位/粒子/着色器代码），不含任何已有
  IP 角色/造型/Logo/素材。

## 10. 全局约束（继承项目惯例）

- 引擎 Godot 4.6.3；测试前必 `--headless --import`；GdUnit4 加 `--ignoreHeadlessMode`。
- 静态类型纪律：禁 `var x := <Variant 表达式>`；`Dictionary.get(...)` → `var x: Variant`
  + 守卫/显式转换。
- `MainMenu` 保留 `class_name`；新增持久化若做，沿用 JSON + `is Dictionary` 守卫。
- 中文对话/注释；标识符英文。trunk-based 在 main。
- 提交 Conventional Commits，body 带 `Story: main-menu-fantasy-redesign (#18)`，
  结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。

## 11. 原创性声明

背景与英雄立绘由用户提供且须为原创；占位回退、粒子、着色器、布局、动效均为原创
代码实现。参考图（如 Dota 2 官方美术）仅用于**氛围与构图范式**借鉴（三人站位、冷暖
对比、雪山史诗感属通用范式），**不复制/仿制**任何具体角色、造型、Logo 或素材。
