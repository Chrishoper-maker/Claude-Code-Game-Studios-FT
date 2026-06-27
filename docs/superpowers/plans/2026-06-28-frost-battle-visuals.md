# 寒霜战场视觉反馈批次 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为已完结的寒霜套装逻辑层补齐战场内视觉反馈：被控单位冰蓝着色+头顶标签、施加飘字、冻结跳过飘字。

**Architecture:** 沿用现有「render 层全部经 EventBus 单向驱动」范式。新增 `frost_applied` / `frost_resolved` 两个 EventBus 信号承载状态变化（逻辑层发射，BLOCKING 单测）；UnitView 提供标记 API、UnitRenderer 订阅置/清标记、DamageFloater 订阅弹飘字（视觉 ADVISORY）。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。

**Spec:** `docs/superpowers/specs/2026-06-28-frost-battle-visuals-design.md`

## Global Constraints

- 引擎 Godot 4.6.3；用 API 前查 `docs/engine-reference/`，不臆测后切版本签名。
- 静态类型：所有变量/参数/返回值显式标注（项目惯例）。
- 测试命名 `test_[scenario]_[expected]`；Arrange/Act/Assert 结构；确定性、无随机/无时序断言。
- 信号名 snake_case 过去式。常量 UPPER_SNAKE_CASE。
- 渲染层数据→视觉单向，禁写回（ADR-0007）。UI/渲染禁拥有或改游戏状态。
- 提交用 Conventional Commits，body 含 `Story: ②b-3 frost-battle-visuals` 与 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 跑测试：`/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 后 `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`。单套件可 `-a res://tests/unit/<file>.gd`。
- `monitor_signals(EventBus, false)` 监听 autoload（false=不 auto_free）；断言 `await assert_signal(monitor).is_emitted("sig", [args])` / `.is_not_emitted("sig")`。

---

### Task 1: `frost_applied` 信号 + `_apply_frost` 发射

**Files:**
- Modify: `src/autoloads/event_bus.gd`（新增信号声明）
- Modify: `src/battle/set_reaction_system.gd:89-98`（`_apply_frost` 发射）
- Test: `tests/unit/set_reactions/set_reaction_frost_signal_test.gd`（新建）

**Interfaces:**
- Produces: `EventBus.frost_applied(unit_id: int, status: StringName)` — 施加成功后发射，status ∈ {`BattleResolution.STATUS_FROST_SLOW/ROOT/FREEZE`}。

- [ ] **Step 1: 写失败测试**

新建 `tests/unit/set_reactions/set_reaction_frost_signal_test.gd`：

```gdscript
# 寒霜施加发射 frost_applied(target, status)；免疫挡掉时不发。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _srs: SetReactionSystem
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new(); _srs = SetReactionSystem.new()
	add_child(_tm); add_child(_br); add_child(_srs)
	_br.setup(_gb, _tm); _srs.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _srs.free(); _gb.free()

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition: return d
	return null

func _register_frost(k: int) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_frost_%s" % _SLOTKEYS[i])
		eq[def.slot] = def
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), eq))

func _register_plain() -> int:
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), {}))

func test_frost_9_emits_frost_applied_freeze() -> void:
	var aid := _register_frost(9)
	var tid := _register_plain()
	var monitor := monitor_signals(EventBus, false)
	_srs.on_attack_executed(aid, tid, 3)
	await assert_signal(monitor).is_emitted("frost_applied", [tid, BattleResolution.STATUS_FROST_FREEZE])

func test_frost_6_emits_frost_applied_root() -> void:
	var aid := _register_frost(6)
	var tid := _register_plain()
	var monitor := monitor_signals(EventBus, false)
	_srs.on_attack_executed(aid, tid, 3)
	await assert_signal(monitor).is_emitted("frost_applied", [tid, BattleResolution.STATUS_FROST_ROOT])

func test_frost_3_emits_frost_applied_slow() -> void:
	var aid := _register_frost(3)
	var tid := _register_plain()
	var monitor := monitor_signals(EventBus, false)
	_srs.on_attack_executed(aid, tid, 3)
	await assert_signal(monitor).is_emitted("frost_applied", [tid, BattleResolution.STATUS_FROST_SLOW])

func test_immune_target_emits_no_frost_applied() -> void:
	var aid := _register_frost(9)
	var tid := _register_plain()
	_br.apply_status(tid, BattleResolution.STATUS_FROST_IMMUNE)
	var monitor := monitor_signals(EventBus, false)
	_srs.on_attack_executed(aid, tid, 3)
	await assert_signal(monitor).is_not_emitted("frost_applied")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/set_reactions/set_reaction_frost_signal_test.gd`
Expected: FAIL — `frost_applied` 信号不存在（监听报无此信号 / 未发射）。

- [ ] **Step 3: 加信号声明**

`src/autoloads/event_bus.gd`，在 `terrain_changed` 信号（`signal terrain_changed(pos: Vector2i, type: String)`）那一行之后新增：

```gdscript
# ── 寒霜/控制状态视觉（frost-battle-visuals）──
signal frost_applied(unit_id: int, status: StringName)     # 施加寒霜成功（渲染层着色+标签+飘字）
signal frost_resolved(unit_id: int, consumed: StringName)  # 敌回合开始消费寒霜（清标签；冻结额外跳过飘字）
```

- [ ] **Step 4: 在 `_apply_frost` 发射**

`src/battle/set_reaction_system.gd`，把 `_apply_frost` 的施加循环改为发射信号：

```gdscript
	for tier in [9, 6, 3]:
		if SetBonus.is_tier_active(attacker, "set_frost", tier):
			_battle_resolution.apply_status(target_id, FROST_STATUS_BY_TIER[tier])
			EventBus.frost_applied.emit(target_id, FROST_STATUS_BY_TIER[tier])
			return
```

- [ ] **Step 5: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/set_reactions/set_reaction_frost_signal_test.gd`
Expected: PASS（4/4）。

- [ ] **Step 6: 提交**

```bash
git add src/autoloads/event_bus.gd src/battle/set_reaction_system.gd tests/unit/set_reactions/set_reaction_frost_signal_test.gd tests/unit/set_reactions/set_reaction_frost_signal_test.gd.uid
git commit -m "feat(battle): emit frost_applied on frost application

Story: ②b-3 frost-battle-visuals

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
（`.uid` 旁车由 `--import` 生成；若不存在则省略该路径。）

---

### Task 2: `frost_resolved` 信号 + `resolve_frost_for_turn` 发射

**Files:**
- Modify: `src/battle/battle_resolution.gd:71-84`（三消费分支发射）
- Test: `tests/unit/battle_resolution/frost_resolved_signal_test.gd`（新建）

**Interfaces:**
- Consumes: `EventBus.frost_resolved` 信号（Task 1 已声明）。
- Produces: `resolve_frost_for_turn` 在 FREEZE/ROOT/SLOW 消费分支各发一次 `frost_resolved(unit_id, consumed)`；免疫到期分支不发。

- [ ] **Step 1: 写失败测试**

新建 `tests/unit/battle_resolution/frost_resolved_signal_test.gd`：

```gdscript
# resolve_frost_for_turn：三消费分支各发 frost_resolved(id, consumed)；无寒霜分支不发。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new()
	add_child(_tm); add_child(_br)
	_br.setup(_gb, _tm)

func after_test() -> void:
	_tm.free(); _br.free(); _gb.free()

func _register() -> int:
	var d := UnitDefinition.new()
	d.id = "e"; d.faction = "enemy"; d.unit_class = "swordsman"
	d.move_range = 4; d.attack_range = 1; d.base_damage = 3; d.max_hp = 6
	return _tm.register_unit(UnitInstance.from_definition(d))

func test_freeze_emits_frost_resolved_freeze() -> void:
	var id := _register()
	_br.apply_status(id, BattleResolution.STATUS_FROST_FREEZE)
	var monitor := monitor_signals(EventBus, false)
	_br.resolve_frost_for_turn(id)
	await assert_signal(monitor).is_emitted("frost_resolved", [id, BattleResolution.STATUS_FROST_FREEZE])

func test_root_emits_frost_resolved_root() -> void:
	var id := _register()
	_br.apply_status(id, BattleResolution.STATUS_FROST_ROOT)
	var monitor := monitor_signals(EventBus, false)
	_br.resolve_frost_for_turn(id)
	await assert_signal(monitor).is_emitted("frost_resolved", [id, BattleResolution.STATUS_FROST_ROOT])

func test_slow_emits_frost_resolved_slow() -> void:
	var id := _register()
	_br.apply_status(id, BattleResolution.STATUS_FROST_SLOW)
	var monitor := monitor_signals(EventBus, false)
	_br.resolve_frost_for_turn(id)
	await assert_signal(monitor).is_emitted("frost_resolved", [id, BattleResolution.STATUS_FROST_SLOW])

func test_no_frost_emits_no_frost_resolved() -> void:
	var id := _register()
	_br.apply_status(id, BattleResolution.STATUS_FROST_IMMUNE)
	var monitor := monitor_signals(EventBus, false)
	_br.resolve_frost_for_turn(id)
	await assert_signal(monitor).is_not_emitted("frost_resolved")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_resolution/frost_resolved_signal_test.gd`
Expected: FAIL — 三发射断言失败（信号未发）。

- [ ] **Step 3: 三分支发射**

`src/battle/battle_resolution.gd`，在 `resolve_frost_for_turn` 三个消费分支的 `return` 之前各加一行发射：

```gdscript
	if get_unit_status(unit_id, STATUS_FROST_FREEZE):
		_consume_status(unit_id, STATUS_FROST_FREEZE)
		apply_status(unit_id, STATUS_FROST_IMMUNE)
		EventBus.frost_resolved.emit(unit_id, STATUS_FROST_FREEZE)
		return {"skip": true, "move_cap": 0}
	if get_unit_status(unit_id, STATUS_FROST_ROOT):
		_consume_status(unit_id, STATUS_FROST_ROOT)
		apply_status(unit_id, STATUS_FROST_IMMUNE)
		EventBus.frost_resolved.emit(unit_id, STATUS_FROST_ROOT)
		return {"skip": false, "move_cap": 0}
	if get_unit_status(unit_id, STATUS_FROST_SLOW):
		_consume_status(unit_id, STATUS_FROST_SLOW)
		apply_status(unit_id, STATUS_FROST_IMMUNE)
		EventBus.frost_resolved.emit(unit_id, STATUS_FROST_SLOW)
		return {"skip": false, "move_cap": u.get_move_range() / 2}   # int 除法 = floor
	_consume_status(unit_id, STATUS_FROST_IMMUNE)   # 无寒霜 → 免疫到期
	return {"skip": false, "move_cap": -1}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_resolution/frost_resolved_signal_test.gd`
Expected: PASS（4/4）。

- [ ] **Step 5: 跑既有寒霜结算回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_resolution/frost_resolution_test.gd`
Expected: PASS（5/5，发射不改返回值，零回归）。

- [ ] **Step 6: 提交**

```bash
git add src/battle/battle_resolution.gd tests/unit/battle_resolution/frost_resolved_signal_test.gd tests/unit/battle_resolution/frost_resolved_signal_test.gd.uid
git commit -m "feat(battle): emit frost_resolved on frost consumption

Story: ②b-3 frost-battle-visuals

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: UnitView 寒霜标记（着色 + 头顶标签 + albedo 通道重构）

**Files:**
- Modify: `src/render/unit_view.gd`（新增标记字段/API + `_current_albedo` 重构）
- Test: `tests/unit/render/unit_frost_marker_test.gd`（新建）

**Interfaces:**
- Produces:
  - `UnitView.FROST_LABEL: Dictionary`（`StringName→String`：滞步/冰封/冻结）— DamageFloater(Task 5) 复用。
  - `UnitView.set_frost_marker(status: StringName) -> void`
  - `UnitView.clear_frost_marker() -> void`

- [ ] **Step 1: 写失败测试**

新建 `tests/unit/render/unit_frost_marker_test.gd`：

```gdscript
# 寒霜标记：set_frost_marker 着色为冰蓝（≠基色）；clear_frost_marker 复原。
# flash_hit 在寒霜态下回到寒霜色而非基色（albedo 通道优先级 frost>dimmed>base）。
extends GdUnitTestSuite

func _view() -> UnitView:
	var v: UnitView = auto_free(UnitView.new())
	add_child(v)
	v.setup("swordsman", "crew", 1, Vector2i(0, 0))
	return v

func _albedo(v: UnitView) -> Color:
	return (v._mesh.material_override as StandardMaterial3D).albedo_color

func test_set_frost_marker_tints_then_clear_restores() -> void:
	var v := _view()
	var base := _albedo(v)
	v.set_frost_marker(BattleResolution.STATUS_FROST_FREEZE)
	assert_object(_albedo(v)).is_not_equal(base)              # 着色改变
	v.clear_frost_marker()
	assert_object(_albedo(v)).is_equal(base)                  # 复原

func test_flash_hit_returns_to_frost_color_when_frosted() -> void:
	var v := _view()
	v.set_frost_marker(BattleResolution.STATUS_FROST_FREEZE)
	var frost_color := _albedo(v)
	v.flash_hit()                                            # 瞬时置白，tween 回正色
	await get_tree().create_timer(0.2).timeout
	assert_object(_albedo(v)).is_equal(frost_color)          # 回到寒霜色（非基色）

func test_frost_label_has_three_tiers() -> void:
	assert_str(UnitView.FROST_LABEL[BattleResolution.STATUS_FROST_SLOW]).is_equal("滞步")
	assert_str(UnitView.FROST_LABEL[BattleResolution.STATUS_FROST_ROOT]).is_equal("冰封")
	assert_str(UnitView.FROST_LABEL[BattleResolution.STATUS_FROST_FREEZE]).is_equal("冻结")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/render/unit_frost_marker_test.gd`
Expected: FAIL — `FROST_LABEL` / `set_frost_marker` 未定义。

- [ ] **Step 3: 加常量与字段**

`src/render/unit_view.gd`，在 `const ENEMY_DARKEN ...` 之后新增：

```gdscript
const FROST_TINT := Color("#7FD8FF")   # 寒霜冰蓝（着色 lerp / 飘字纯色，spec §4）
const FROST_TINT_MIX := 0.5            # 基色↔冰色混合比例
const FROST_LABEL := {                 # status → 头顶标签文案（DamageFloater 复用，飘字另加 "!"）
	&"FROST_SLOW": "滞步",
	&"FROST_ROOT": "冰封",
	&"FROST_FREEZE": "冻结",
}
```

并在变量区（`var _dimmed: bool = false` 之后）新增：

```gdscript
var _frost_status: StringName = &""   # 当前寒霜标记（&"" = 无）
var _frost_label: Label3D             # 头顶寒霜标签
```

- [ ] **Step 4: 重构 albedo 解析 + flash_hit/set_dimmed 统一走它**

`src/render/unit_view.gd`，替换 `flash_hit`、`set_dimmed`、`_dimmed_albedo` 为统一解析：

```gdscript
# 命中闪白再回当前正色（~0.15s）。由 UnitRenderer 在 damage_dealt 时调用。
func flash_hit() -> void:
	if _mesh == null:
		return
	var mat := _mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = Color.WHITE
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color", _current_albedo(), 0.15)

# 本回合已结束 → 整体压暗 albedo（与 set_selected 的 emission 通道分离，不互相覆盖）。
func set_dimmed(enabled: bool) -> void:
	_dimmed = enabled
	_apply_albedo()

# albedo 通道优先级：frost > dimmed > base（spec §3.3）。
func _current_albedo() -> Color:
	if _frost_status != &"":
		return _base_albedo.lerp(FROST_TINT, FROST_TINT_MIX)
	if _dimmed:
		return _base_albedo.darkened(0.55)
	return _base_albedo

func _apply_albedo() -> void:
	if _mesh == null:
		return
	var mat := _mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = _current_albedo()
```

- [ ] **Step 5: 加寒霜标记 API**

`src/render/unit_view.gd` 末尾新增：

```gdscript
# 设寒霜标记：冰蓝着色 + 头顶标签（滞步/冰封/冻结）。faction 无关，仅按信号驱动。
func set_frost_marker(status: StringName) -> void:
	_frost_status = status
	_apply_albedo()
	if _frost_label == null:
		_frost_label = Label3D.new()
		_frost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_frost_label.no_depth_test = true
		_frost_label.pixel_size = 0.006
		_frost_label.font_size = 40
		_frost_label.outline_size = 10
		_frost_label.outline_modulate = Color.BLACK
		_frost_label.modulate = FROST_TINT
		_frost_label.position = Vector3(0, 1.6, 0)   # HP 标签(1.95)下方
		add_child(_frost_label)
	_frost_label.text = FROST_LABEL.get(status, "")
	_frost_label.visible = true

# 清寒霜标记：复原 albedo + 隐藏标签。
func clear_frost_marker() -> void:
	_frost_status = &""
	_apply_albedo()
	if _frost_label != null:
		_frost_label.visible = false
```

- [ ] **Step 6: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/render/unit_frost_marker_test.gd`
Expected: PASS（3/3）。

- [ ] **Step 7: 跑既有变灰回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/render/unit_dim_test.gd`
Expected: PASS（2/2，set_dimmed 改走 `_apply_albedo` 行为等价）。

- [ ] **Step 8: 提交**

```bash
git add src/render/unit_view.gd tests/unit/render/unit_frost_marker_test.gd tests/unit/render/unit_frost_marker_test.gd.uid
git commit -m "feat(render): UnitView frost marker (ice tint + head label)

Story: ②b-3 frost-battle-visuals

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: UnitRenderer 订阅置/清标记

**Files:**
- Modify: `src/render/unit_renderer.gd`（订阅 frost_applied/frost_resolved）
- Test: `tests/unit/render/unit_frost_marker_test.gd`（追加 renderer 用例）

**Interfaces:**
- Consumes: `EventBus.frost_applied/frost_resolved`（Task 1/2）、`UnitView.set_frost_marker/clear_frost_marker`（Task 3）。

- [ ] **Step 1: 追加失败测试**

`tests/unit/render/unit_frost_marker_test.gd` 末尾追加：

```gdscript
func test_renderer_tints_on_frost_applied_and_clears_on_resolved() -> void:
	var r: UnitRenderer = auto_free(UnitRenderer.new())
	add_child(r)
	var v := r.spawn_view("swordsman", "enemy", 9, Vector2i(0, 0))
	var base := _albedo(v)
	EventBus.frost_applied.emit(9, BattleResolution.STATUS_FROST_FREEZE)
	assert_object(_albedo(v)).is_not_equal(base)     # 着色
	EventBus.frost_resolved.emit(9, BattleResolution.STATUS_FROST_FREEZE)
	assert_object(_albedo(v)).is_equal(base)          # 复原
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/render/unit_frost_marker_test.gd`
Expected: FAIL — `test_renderer_tints_on_frost_applied_and_clears_on_resolved` 着色未变（未订阅）。

- [ ] **Step 3: 加订阅**

`src/render/unit_renderer.gd`，在 `_ready()` 末尾（`player_phase_started` 连接之后）新增：

```gdscript
	if not EventBus.frost_applied.is_connected(_on_frost_applied):
		EventBus.frost_applied.connect(_on_frost_applied)      # 施加 → 着色+标签
	if not EventBus.frost_resolved.is_connected(_on_frost_resolved):
		EventBus.frost_resolved.connect(_on_frost_resolved)    # 消费 → 清标记
```

并在文件末尾新增处理器：

```gdscript
func _on_frost_applied(unit_id: int, status: StringName) -> void:
	var v: UnitView = _views.get(unit_id, null)
	if v != null:
		v.set_frost_marker(status)

func _on_frost_resolved(unit_id: int, _consumed: StringName) -> void:
	var v: UnitView = _views.get(unit_id, null)
	if v != null:
		v.clear_frost_marker()
```

- [ ] **Step 4: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/render/unit_frost_marker_test.gd`
Expected: PASS（4/4）。

- [ ] **Step 5: 提交**

```bash
git add src/render/unit_renderer.gd tests/unit/render/unit_frost_marker_test.gd
git commit -m "feat(render): UnitRenderer drives frost marker via signals

Story: ②b-3 frost-battle-visuals

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: DamageFloater 寒霜飘字（施加 + 冻结跳过）

**Files:**
- Modify: `src/render/damage_floater.gd`（订阅 + 飘字文案静态助手）
- Test: `tests/unit/damage_floater/damage_floater_frost_test.gd`（新建）

**Interfaces:**
- Consumes: `EventBus.frost_applied/frost_resolved`（Task 1/2）、`UnitView.FROST_LABEL`（Task 3）、`BattleResolution.STATUS_FROST_*`。
- Produces: `DamageFloater.frost_text(status: StringName) -> String`（"滞步!"/"冰封!"/"冻结!"，纯文案，可单测）。

> 说明：飘字的实际生成依赖 `get_camera_3d()`，无头测试无相机故只能测纯文案助手与「订阅不崩」；飘字出现/上浮属 AC-7/8 视觉 ADVISORY，F5 截图验收。

- [ ] **Step 1: 写失败测试**

新建 `tests/unit/damage_floater/damage_floater_frost_test.gd`：

```gdscript
# 寒霜飘字文案助手 + 订阅 frost_applied/frost_resolved 不崩（无相机优雅跳过）。
extends GdUnitTestSuite

func _floater() -> DamageFloater:
	var f: DamageFloater = auto_free(DamageFloater.new())
	var r: UnitRenderer = auto_free(UnitRenderer.new())
	add_child(r); add_child(f)
	f.setup(r, func(_id: int) -> String: return "enemy")
	return f

func test_frost_text_maps_three_tiers() -> void:
	assert_str(DamageFloater.frost_text(BattleResolution.STATUS_FROST_SLOW)).is_equal("滞步!")
	assert_str(DamageFloater.frost_text(BattleResolution.STATUS_FROST_ROOT)).is_equal("冰封!")
	assert_str(DamageFloater.frost_text(BattleResolution.STATUS_FROST_FREEZE)).is_equal("冻结!")

func test_frost_signals_do_not_crash_without_camera() -> void:
	var f := _floater()
	EventBus.frost_applied.emit(1, BattleResolution.STATUS_FROST_FREEZE)     # 无相机 → 静默跳过
	EventBus.frost_resolved.emit(1, BattleResolution.STATUS_FROST_FREEZE)
	assert_object(f).is_not_null()   # 走到此处即未崩
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/damage_floater/damage_floater_frost_test.gd`
Expected: FAIL — `frost_text` 未定义。

- [ ] **Step 3: 加文案助手 + 订阅 + 处理器**

`src/render/damage_floater.gd`，在 `damage_color` 静态函数之后新增：

```gdscript
static func frost_text(status: StringName) -> String:
	return UnitView.FROST_LABEL.get(status, "") + "!"
```

在 `setup()` 的信号连接区（`unit_downed.connect` 之后）新增：

```gdscript
	if not EventBus.frost_applied.is_connected(_on_frost_applied):
		EventBus.frost_applied.connect(_on_frost_applied)
	if not EventBus.frost_resolved.is_connected(_on_frost_resolved):
		EventBus.frost_resolved.connect(_on_frost_resolved)
```

在文件末尾新增处理器（复用既有 `_spawn`）：

```gdscript
# 施加寒霜 → 弹对应飘字（滞步!/冰封!/冻结!）。
func _on_frost_applied(unit_id: int, status: StringName) -> void:
	_spawn(unit_id, frost_text(status), UnitView.FROST_TINT, 36, FLOAT_DURATION, false)

# 冻结被结算跳过 → 弹「冻结·跳过」；root/slow 仅清标记不弹（避免刷屏）。
func _on_frost_resolved(unit_id: int, consumed: StringName) -> void:
	if consumed == BattleResolution.STATUS_FROST_FREEZE:
		_spawn(unit_id, "冻结·跳过", UnitView.FROST_TINT, 36, FLOAT_DURATION, false)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/damage_floater/damage_floater_frost_test.gd`
Expected: PASS（2/2）。

- [ ] **Step 5: 跑既有飘字回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/damage_floater/damage_floater_test.gd`
Expected: PASS（既有用例零回归）。

- [ ] **Step 6: 提交**

```bash
git add src/render/damage_floater.gd tests/unit/damage_floater/damage_floater_frost_test.gd tests/unit/damage_floater/damage_floater_frost_test.gd.uid
git commit -m "feat(render): DamageFloater frost floaters (apply + freeze-skip)

Story: ②b-3 frost-battle-visuals

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 全量回归 + 视觉验收清单

**Files:** 无新增（验证 + 文档）。

- [ ] **Step 1: 全量测试**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
Expected: 全绿（既有 495 + 本批新增 ~13），零失败/错误/孤儿。

- [ ] **Step 2: 记录视觉验收清单**

确认以下 ADVISORY 项留给人眼 F5（写入最终报告/进度）：
- AC-6：被冻结敌人呈冰蓝着色 + 头顶「冻结」标签。
- AC-7：施加瞬间弹对应飘字（滞步!/冰封!/冻结!）。
- AC-8：冻结敌回合被跳过时弹「冻结·跳过」。

- [ ] **Step 3: 无新增代码则跳过提交**（仅验证步）。

---

## Self-Review

**Spec 覆盖**：
- §3.2 frost_applied → Task 1 ✓；frost_resolved → Task 2 ✓。
- §3.3.1 UnitView 标记+albedo 重构 → Task 3 ✓。
- §3.3.2 UnitRenderer 订阅 → Task 4 ✓。
- §3.3.3 DamageFloater 飘字 → Task 5 ✓。
- §4 常量（FROST_TINT/lerp 0.5/文案 dict）→ Task 3 ✓。
- §8 AC-1..4 → Task 1/2 测试 ✓；AC-5 全量 → Task 6 ✓；AC-6..8 视觉 → Task 6 清单 ✓。
- §5 边界（同帧致死/免疫/无寒霜/view 空/击倒）：施加守卫与发射点在 `_apply_frost` 守卫之后（Task 1）；无寒霜不发（Task 2 AC-4）；view 空守卫（Task 4/5 处理器 null 检查）；击倒 set_downed 隐藏整 view（既有，无需改）✓。

**占位符扫描**：无 TBD/TODO；每个代码步均含完整代码与确切命令/预期。

**类型一致性**：`set_frost_marker(status: StringName)`、`clear_frost_marker()`、`FROST_LABEL`、`frost_text(status: StringName)->String`、信号签名 `frost_applied(int,StringName)`/`frost_resolved(int,StringName)` 跨 Task 1→5 引用一致。`UnitView.FROST_TINT`/`FROST_LABEL` 在 Task 3 定义、Task 5 复用，名称一致。
