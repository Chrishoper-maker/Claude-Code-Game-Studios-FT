# 战斗反馈/演出 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给可玩战斗循环加白盒打击感——命中闪光、伤害/治疗浮字、KO 特效、震屏、胜负结算页。

**Architecture:** 5 个职责单一的视觉部件订阅既有 EventBus 信号（damage_dealt/heal_executed/unit_downed/battle_won/lost），把战斗结果翻译成 Tween 演出。不碰战斗逻辑。BattleScene 接线并临时断开 RunManager 航线跳转（防胜利时 goto_route 崩）。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。白盒：图元 + Control + Label3D + Tween，零美术/音效。

## Global Constraints

- 引擎 Godot 4.6.3；二进制 `/Applications/Godot.app/Contents/MacOS/Godot`。
- 配色权威（battle-hud GDD）：敌伤红 `#FF2222`、友伤橙 `#FF8800`、治疗绿 `#22FF66`。浮字时长 ~0.6s。
- 坐标走 `GridCoordMapper`；相机经 `get_viewport().get_camera_3d()` 取（与 PlayerTurnController 拾取一致）。
- **几乎全视觉 → 验证 = 导入零错 + F5 目视（ADVISORY gate）**；仅 DamageFloater 选色有一条单测。
- 提交需用户授权（CLAUDE.md）；Conventional Commits，body 引用本计划，结尾加 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 跑测试：`<godot> --headless --import` 然后 `<godot> --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit -a res://tests/integration`。
- 既有信号签名：`damage_dealt(target_id:int, final_damage:int, new_hp:int)`、`heal_executed(target_id:int, amount:int)`、`unit_downed(unit_id:int)`、`battle_won()`、`battle_lost()`。

## 文件结构

| 文件 | 责任 | 动作 |
|------|------|------|
| `src/render/damage_floater.gd` | 伤害/治疗浮字 + KO 特效（含静态选色） | 新建 |
| `src/render/unit_view.gd` | flash_hit() 命中闪光 + set_downed() KO 退场 | 修改 |
| `src/render/unit_renderer.gd` | damage_dealt 时触发 flash_hit | 修改 |
| `src/fx/camera_shake.gd` | 震屏（ADR-0009） | 新建 |
| `src/ui/battle_result_overlay.gd` | 胜负结算页 + 重新开始 | 新建 |
| `src/board/grid_board_3d.gd` | 暴露相机（供 CameraShake/Floater 不必要——用 get_viewport），仅确认无需改 | 不改 |
| `src/battle/battle_scene.gd` | 接线 5 部件 + 断开 RunManager 跳转 | 修改 |
| `scenes/BattleScene.tscn` | 加 DamageFloater/CameraShake/BattleResultOverlay 节点 | 修改 |
| `tests/unit/damage_floater/damage_floater_test.gd` | 选色单测 | 新建 |

---

### Task 1: DamageFloater — 浮字 + KO（含选色单测）

**Files:**
- Create: `src/render/damage_floater.gd`
- Test: `tests/unit/damage_floater/damage_floater_test.gd`

**Interfaces:**
- Consumes: `UnitRenderer.get_view(id) -> UnitView`（既有，返回 view 或 null；view.global_position 为世界坐标）；`EventBus.damage_dealt/heal_executed/unit_downed`。
- Produces:
  - `class_name DamageFloater extends Control`
  - `static func damage_color(faction: String) -> Color`（crew→橙 / 否则→红）
  - `setup(unit_renderer: UnitRenderer, faction_lookup: Callable) -> void`

- [ ] **Step 1: 写选色失败测试**

```gdscript
# tests/unit/damage_floater/damage_floater_test.gd
extends GdUnitTestSuite

func test_damage_color_enemy_is_red() -> void:
	assert_object(DamageFloater.damage_color("enemy")).is_equal(Color("#FF2222"))

func test_damage_color_crew_is_orange() -> void:
	assert_object(DamageFloater.damage_color("crew")).is_equal(Color("#FF8800"))
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/damage_floater`
Expected: FAIL（DamageFloater 不存在）。

- [ ] **Step 3: 实现**

```gdscript
# src/render/damage_floater.gd
# 伤害/治疗浮字 + KO 特效（CanvasLayer 下 Control，纯视觉）。订阅战斗结果信号，把数字飘在单位头顶。
# 位置 = 相机反投影单位世界坐标（HUD GDD OQ-3：2D 层 + unproject_position）。
class_name DamageFloater
extends Control

const FLOAT_DURATION: float = 0.6
const KO_DURATION: float = 0.7
const RISE_PX: float = 44.0
const HEAL_COLOR := Color("#22FF66")

var _unit_renderer: UnitRenderer
var _faction_lookup: Callable

static func damage_color(faction: String) -> Color:
	return Color("#FF8800") if faction == "crew" else Color("#FF2222")

func setup(unit_renderer: UnitRenderer, faction_lookup: Callable) -> void:
	_unit_renderer = unit_renderer
	_faction_lookup = faction_lookup
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not EventBus.damage_dealt.is_connected(_on_damage):
		EventBus.damage_dealt.connect(_on_damage)
	if not EventBus.heal_executed.is_connected(_on_heal):
		EventBus.heal_executed.connect(_on_heal)
	if not EventBus.unit_downed.is_connected(_on_downed):
		EventBus.unit_downed.connect(_on_downed)

func _on_damage(target_id: int, final_damage: int, _new_hp: int) -> void:
	var faction: String = _faction_lookup.call(target_id) if _faction_lookup.is_valid() else "enemy"
	_spawn(target_id, "-%d" % final_damage, damage_color(faction), 40, FLOAT_DURATION, false)

func _on_heal(target_id: int, amount: int) -> void:
	_spawn(target_id, "+%d" % amount, HEAL_COLOR, 40, FLOAT_DURATION, false)

func _on_downed(unit_id: int) -> void:
	_spawn(unit_id, "KO", Color("#FF3333"), 96, KO_DURATION, true)

func _spawn(unit_id: int, text: String, color: Color, font_size: int, duration: float, punch: bool) -> void:
	if _unit_renderer == null:
		return
	var view := _unit_renderer.get_view(unit_id)
	if view == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var world: Vector3 = view.global_position + Vector3(0, 1.6, 0)
	if cam.is_position_behind(world):
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	add_child(label)
	label.position = cam.unproject_position(world) - label.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - RISE_PX, duration)
	tw.tween_property(label, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	if punch:
		label.pivot_offset = label.size * 0.5
		label.scale = Vector2(1.4, 1.4)
		tw.tween_property(label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(label.queue_free)
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令。Expected: PASS（2 选色测试）。

- [ ] **Step 5: 提交**（须用户授权）

```bash
git add src/render/damage_floater.gd tests/unit/damage_floater/damage_floater_test.gd
git commit -m "feat(fx): DamageFloater damage/heal/KO popups

Plan: docs/superpowers/plans/2026-06-20-combat-feedback.md Task 1
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: UnitView.flash_hit() — 命中闪光

**Files:**
- Modify: `src/render/unit_view.gd`（`_build_whitebox` 存 `_base_albedo`；新增 `flash_hit`）

**Interfaces:**
- Produces: `UnitView.flash_hit() -> void`（瞬白再回原色）。

- [ ] **Step 1: 实现（视觉，无单测）**

在成员区加 `var _base_albedo: Color`；`_build_whitebox` 内 `mat.albedo_color = base` 之后加 `_base_albedo = base`。
新增方法：

```gdscript
# 命中闪白再回原色（~0.15s）。由 UnitRenderer 在 damage_dealt 时调用。
func flash_hit() -> void:
	if _mesh == null:
		return
	var mat := _mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = Color.WHITE
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color", _base_albedo, 0.15)
```

- [ ] **Step 2: 导入校验**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo OK`
Expected: OK。

- [ ] **Step 3: 提交**（须用户授权）

```bash
git add src/render/unit_view.gd
git commit -m "feat(fx): UnitView.flash_hit white flash on hit

Plan: docs/superpowers/plans/2026-06-20-combat-feedback.md Task 2
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: UnitView.set_downed() — KO 退场（下沉+缩小）

**Files:**
- Modify: `src/render/unit_view.gd`（替换 `set_downed`）

**Interfaces:**
- Consumes/Produces: `UnitView.set_downed() -> void`（既有签名；改为退场 Tween）。

- [ ] **Step 1: 实现（视觉，无单测）**

替换 `set_downed`：

```gdscript
# 击倒退场：快速下沉 + 缩小后隐藏（KO 大字由 DamageFloater 同时弹出）。
func set_downed() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:y", position.y - 0.5, 0.3)
	tw.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.3)
	tw.chain().tween_callback(func() -> void: visible = false)
```

- [ ] **Step 2: 导入校验**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo OK`
Expected: OK。

- [ ] **Step 3: 提交**（须用户授权）

```bash
git add src/render/unit_view.gd
git commit -m "feat(fx): UnitView KO sink+shrink exit on downed

Plan: docs/superpowers/plans/2026-06-20-combat-feedback.md Task 3
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: CameraShake — 震屏（ADR-0009）

**Files:**
- Create: `src/fx/camera_shake.gd`

**Interfaces:**
- Consumes: `EventBus.damage_dealt`；一个 `Camera3D`。
- Produces: `class_name CameraShake extends Node`；`setup(camera: Camera3D) -> void`；`shake(intensity: float) -> void`。

- [ ] **Step 1: 实现（视觉，无单测）**

```gdscript
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
```

- [ ] **Step 2: 导入校验**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo OK`
Expected: OK。

- [ ] **Step 3: 提交**（须用户授权）

```bash
git add src/fx/camera_shake.gd
git commit -m "feat(fx): CameraShake on hit (ADR-0009)

Plan: docs/superpowers/plans/2026-06-20-combat-feedback.md Task 4
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: BattleResultOverlay — 胜负结算页

**Files:**
- Create: `src/ui/battle_result_overlay.gd`

**Interfaces:**
- Consumes: `EventBus.battle_won/battle_lost`；`get_tree().reload_current_scene()`。
- Produces: `class_name BattleResultOverlay extends Control`；`setup() -> void`。

- [ ] **Step 1: 实现（视觉，无单测）**

```gdscript
# src/ui/battle_result_overlay.gd
# 胜负结算页（Control，挂高层 CanvasLayer）。战斗终态显示结果 + 重新开始。
class_name BattleResultOverlay
extends Control

var _title: Label

func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	_build_ui()
	visible = false
	if not EventBus.battle_won.is_connected(_on_won):
		EventBus.battle_won.connect(_on_won)
	if not EventBus.battle_lost.is_connected(_on_lost):
		EventBus.battle_lost.connect(_on_lost)

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 72)
	box.add_child(_title)

	var btn := Button.new()
	btn.text = "重新开始"
	btn.custom_minimum_size = Vector2(160, 56)
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(func() -> void: get_tree().reload_current_scene())
	box.add_child(btn)

func _on_won() -> void:
	_show("胜利!", Color("#FFD24A"))

func _on_lost() -> void:
	_show("失败…", Color("#FF5555"))

func _show(text: String, color: Color) -> void:
	_title.text = text
	_title.add_theme_color_override("font_color", color)
	visible = true
```

- [ ] **Step 2: 导入校验**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo OK`
Expected: OK。

- [ ] **Step 3: 提交**（须用户授权）

```bash
git add src/ui/battle_result_overlay.gd
git commit -m "feat(ui): BattleResultOverlay win/lose + restart

Plan: docs/superpowers/plans/2026-06-20-combat-feedback.md Task 5
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 接线进 BattleScene + UnitRenderer flash + 断 RunManager + F5

**Files:**
- Modify: `scenes/BattleScene.tscn`
- Modify: `src/battle/battle_scene.gd`
- Modify: `src/render/unit_renderer.gd`

**Interfaces:**
- Consumes: 全部前序产出。

- [ ] **Step 1: BattleScene.tscn 加节点**

加 3 个 ext_resource 与节点（DamageFloater/BattleResultOverlay 挂各自 CanvasLayer；CameraShake 挂根）。
DamageFloater 放 HUDLayer（layer=5），BattleResultOverlay 放 BurstLayer（layer=10，盖 HUD）：

```
[ext_resource type="Script" path="res://src/render/damage_floater.gd" id="14_df"]
[ext_resource type="Script" path="res://src/fx/camera_shake.gd" id="15_cs"]
[ext_resource type="Script" path="res://src/ui/battle_result_overlay.gd" id="16_ro"]
```

```
[node name="DamageFloater" type="Control" parent="HUDLayer"]
script = ExtResource("14_df")

[node name="CameraShake" type="Node" parent="."]
script = ExtResource("15_cs")

[node name="BattleResultOverlay" type="Control" parent="BurstLayer"]
script = ExtResource("16_ro")
```

（load_steps 计数 +3。）

- [ ] **Step 2: UnitRenderer 在 damage_dealt 触发 flash_hit**

`src/render/unit_renderer.gd` 的 `_on_hp_changed` 末尾加 flash：

```gdscript
func _on_hp_changed(target_id: int, _final_damage: int, new_hp: int) -> void:
	var v: UnitView = _views.get(target_id, null)
	if v != null:
		v.set_hp(new_hp, _max_hp.get(target_id, new_hp))
		v.flash_hit()
```

- [ ] **Step 3: battle_scene.gd 接线 + 断 RunManager 跳转**

加 @onready 引用与接线。在 `_ready()` 开头断开 RunManager 航线跳转（TEMP）：

```gdscript
@onready var _damage_floater: DamageFloater = $HUDLayer/DamageFloater
@onready var _camera_shake: CameraShake = $CameraShake
@onready var _battle_result_overlay: BattleResultOverlay = $BurstLayer/BattleResultOverlay
```

`_ready()` 内（在现有 setup 序列附近）：

```gdscript
	# TEMP：航线/招募元层未做 → 断开 RunManager 的胜利跳转（否则 goto_route 因 route_scene 未赋值 assert 崩）。
	if EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.disconnect(RunManager._on_battle_won)
	_damage_floater.setup(_unit_renderer, func(id: int) -> String: return _faction_of(id))
	_camera_shake.setup(get_viewport().get_camera_3d())
	_battle_result_overlay.setup()
```

并新增辅助：

```gdscript
func _faction_of(battle_id: int) -> String:
	var u := _turn_manager.get_unit(battle_id)
	return u.definition.faction if u != null else "enemy"
```

注意：`_camera_shake.setup` 须在 GridBoard3D._ready 建好相机之后调用。BattleScene._ready 晚于子节点 _ready
（Godot 自底向上），故 `get_viewport().get_camera_3d()` 此时已可取到相机。

- [ ] **Step 4: 导入 + 全量回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit -a res://tests/integration`
Expected: 全 PASS（既有 242 + DamageFloater 选色 2 = 244）。⚠️ 集成测试 full_battle_test 实例化 BattleScene
会触发新 setup；断开 RunManager 跳转后，其 before/after_test 的断开/恢复仍兼容（is_connected 守卫）。

- [ ] **Step 5: F5 手动验收（ADVISORY，交用户目视签字）**

用户 F5，核对 spec 验收：
- AC-1：普攻 → 目标头顶 `-N`（敌红/友橙）+ 闪白 + 轻微震屏。
- AC-2：治疗 → 绿 `+N`（MVP crew 无治疗职业上场，触发需后续；可暂跳过目视）。
- AC-3：打死单位 → 弹"KO"大字 + 本体下沉缩小退场。
- AC-4：敌全灭 → "胜利!" + [重新开始] 重载再战；我全灭 → "失败…"。
- AC-5：胜利不崩（RunManager 跳转已断）。

- [ ] **Step 6: 提交**（须用户授权）

```bash
git add scenes/BattleScene.tscn src/battle/battle_scene.gd src/render/unit_renderer.gd
git commit -m "feat(battle): wire combat feedback (floater/shake/result) into BattleScene

Plan: docs/superpowers/plans/2026-06-20-combat-feedback.md Task 6
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## 实现顺序
Task 1（DamageFloater）→ 2/3（UnitView flash/KO）→ 4（CameraShake）→ 5（ResultOverlay）→ 6（接线+F5）。
1-5 可独立做（互不依赖）；6 汇总接线 + F5。

## 自评摘要
- spec 5 部件 → Task 1-5 一一对应；BattleScene 接线 + 断 RunManager + UnitRenderer flash → Task 6。
- 唯一可测逻辑（选色按阵营）→ Task 1 单测覆盖。其余视觉 ADVISORY。
- 风险：CameraShake 抖动幅度/KO 大小/飘字时长为体感值，F5 后按手感调常量。
