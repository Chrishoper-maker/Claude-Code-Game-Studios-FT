# 玩家回合输入 + 白盒战斗 HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让玩家在自己单位的 ACTIVE_TURN 通过动作栏按钮+点格，指挥当前 crew 单位移动/普攻/职业动词/触发爆发/结束回合，配白盒 HUD 与棋盘高亮反馈。

**Architecture:** 三个职责单一的节点挂在 BattleScene 下——`PlayerTurnController`(输入状态机+动作派发，逻辑可单测) + `BoardHighlighter`(3D 格高亮，纯视觉) + `BattleHUD`(2D 动作栏+状态，纯视觉)；外加 UnitView 头顶 HP Label3D 与 GridBoard 补发 unit_moved。本系统不产生战斗逻辑，只把输入翻译成对既有已测子系统的调用。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4 测试框架。白盒视觉（图元 Mesh + Control，零 PNG 美术）。

## Global Constraints

- 引擎钉死 **Godot 4.6.3**；二进制路径 `/Applications/Godot.app/Contents/MacOS/Godot`。
- 测试框架 **GdUnit4**；测试位于 `tests/`，命名 `[system]_[feature]_test.gd`，函数 `test_[scenario]_[expected]`。
- 跑测试命令（先 `--import` 建全局类名缓存，再跑）：
  ```
  /Applications/Godot.app/Contents/MacOS/Godot --headless --import
  /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit -a res://tests/integration
  ```
- 坐标约定：`Vector2i(x=col, y=row)`；逻辑格↔世界坐标一律走 `GridCoordMapper`，禁止内联 `col*CELL_SIZE`。
- 命名：类 PascalCase、变量/信号 snake_case、信号过去式、常量 UPPER_SNAKE。
- 依赖注入优先于单例（DI over singletons）。Gameplay 数值数据驱动，不硬编码。
- **提交需用户授权**（CLAUDE.md「No commits without user instruction」）。计划内的 commit 步骤在执行时须先获用户许可。Conventional Commits + 在 body 引用本计划。提交信息结尾加：`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 测试隔离：单测若可能驱动到 `battle_won`（敌方全灭），须在 `before_test` 断开 `EventBus.battle_won.disconnect(RunManager._on_battle_won)`、`after_test` 恢复（否则触发 RunManager→SceneManager assert）。
- 既有事实：`execute_attack` 内部已 `mark_has_acted`；`execute_slash`/`execute_guard` 内部已 `mark_has_used_verb`；`forced_move_unit` 只改棋盘占用（**不** mark_has_moved、**不**写 UnitInstance.grid_position）。

## 文件结构

| 文件 | 责任 | 动作 |
|------|------|------|
| `src/board/grid_board.gd` | 补发 `unit_moved` | 修改 |
| `src/battle/player_turn_controller.gd` | 输入状态机 + 合法目标 + 动作派发（核心，可测） | 新建 |
| `src/board/board_highlighter.gd` | 棋盘格高亮（纯视觉） | 新建 |
| `src/ui/battle_hud.gd` | 动作栏 + 当前单位状态 + 槽 + 轮次（纯视觉） | 新建 |
| `src/render/unit_view.gd` | 头顶 HP Label3D | 修改 |
| `src/render/unit_renderer.gd` | 订阅 damage/heal 更新 HP | 修改 |
| `src/battle/battle_scene.gd` | 接线新节点 | 修改 |
| `scenes/BattleScene.tscn` | 加 PlayerTurnController/BoardHighlighter/BattleHUD 节点 | 修改 |
| `tests/unit/grid_board/grid_board_move_signal_test.gd` | unit_moved emit 测试 | 新建 |
| `tests/unit/player_turn_controller/player_turn_controller_test.gd` | 控制器逻辑测试 | 新建 |

---

### Task 1: GridBoard 补发 unit_moved

**Files:**
- Modify: `src/board/grid_board.gd:51-55`（`forced_move_unit`）
- Test: `tests/unit/grid_board/grid_board_move_signal_test.gd`

**Interfaces:**
- Consumes: `EventBus.unit_moved(unit_id: int, from_pos: Vector2i, to_pos: Vector2i)`（既有信号）；`GridBoard.place_unit(id, pos)`、`GridBoard.forced_move_unit(id, dest)`、`GridBoard.get_unit_pos(id)`。
- Produces: `forced_move_unit` 在移动后 emit `unit_moved(id, from, dest)`。

- [ ] **Step 1: 写失败测试**

```gdscript
# tests/unit/grid_board/grid_board_move_signal_test.gd
extends GdUnitTestSuite

func test_forced_move_unit_emits_unit_moved() -> void:
	var gb: GridBoard = auto_free(GridBoard.new())
	gb.place_unit(7, Vector2i(1, 1))
	var events: Array = []
	var cb := func(id: int, from_pos: Vector2i, to_pos: Vector2i) -> void:
		events.append([id, from_pos, to_pos])
	EventBus.unit_moved.connect(cb)
	gb.forced_move_unit(7, Vector2i(1, 2))
	EventBus.unit_moved.disconnect(cb)
	assert_int(events.size()).is_equal(1)
	assert_int(events[0][0]).is_equal(7)
	assert_vector(events[0][1]).is_equal(Vector2i(1, 1))
	assert_vector(events[0][2]).is_equal(Vector2i(1, 2))
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/grid_board/grid_board_move_signal_test.gd`
Expected: FAIL（events.size()==0，未发信号）

- [ ] **Step 3: 最小实现**

`src/board/grid_board.gd` 把 `forced_move_unit` 改为：

```gdscript
func forced_move_unit(id: int, dest: Vector2i) -> void:
	var from_pos: Vector2i = _unit_pos.get(id, dest)
	if _unit_pos.has(id):
		_occupancy.erase(_unit_pos[id])
	_occupancy[dest] = id
	_unit_pos[id] = dest
	EventBus.unit_moved.emit(id, from_pos, dest)
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: 全量回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit -a res://tests/integration`
Expected: Overall Summary 全 PASS（EnemyAI 执行测试不应因新信号失败；若失败，检查是否有测试断言 unit_moved 缺席并修正断言）。

- [ ] **Step 6: 提交**（须用户授权）

```bash
git add src/board/grid_board.gd tests/unit/grid_board/grid_board_move_signal_test.gd
git commit -m "feat(board): forced_move_unit emits unit_moved (HUD GDD line 182)

Plan: docs/superpowers/plans/2026-06-20-player-turn-input-hud.md Task 1
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: PlayerTurnController 骨架 + 回合归属

**Files:**
- Create: `src/battle/player_turn_controller.gd`
- Test: `tests/unit/player_turn_controller/player_turn_controller_test.gd`

**Interfaces:**
- Consumes: `EventBus.unit_turn_started(unit_id)`、`unit_turn_ended(unit_id)`、`battle_won()`、`battle_lost()`；`TurnManager.get_unit(id) -> UnitInstance`；`UnitInstance.definition.faction`、`UnitInstance.is_alive`。
- Produces:
  - `class_name PlayerTurnController extends Node`
  - `enum Mode { IDLE, MOVE, ATTACK, BURST_LEAD, BURST_PARTNER }`
  - `setup(turn_manager, grid_board, battle_resolution, bond_gauge_burst, highlighter=null, hud=null) -> void`
  - `is_active() -> bool`、`get_mode() -> int`、`get_current_unit_id() -> int`、`get_valid_targets() -> Array[Vector2i]`
  - `_on_unit_turn_started(unit_id: int) -> void`（信号处理；缓存当前单位 + 判定接管）

- [ ] **Step 1: 写失败测试**

```gdscript
# tests/unit/player_turn_controller/player_turn_controller_test.gd
extends GdUnitTestSuite

func before_test() -> void:
	if EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.disconnect(RunManager._on_battle_won)

func after_test() -> void:
	if not EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.connect(RunManager._on_battle_won)

func _make_def(faction: String, unit_class: String, dmg: int, move_range: int, hp: int, verb: String) -> UnitDefinition:
	var d := UnitDefinition.new()
	d.id = "%s_%s" % [faction, unit_class]
	d.faction = faction
	d.unit_class = unit_class
	d.base_damage = dmg
	d.move_range = move_range
	d.attack_range = 1
	d.max_hp = hp
	d.class_action_id = verb
	return d

func _register(tm: TurnManager, gb: GridBoard, def: UnitDefinition, pos: Vector2i) -> int:
	var inst := UnitInstance.from_definition(def)
	inst.grid_position = pos
	var bid := tm.register_unit(inst)
	gb.place_unit(bid, pos)
	return bid

func _make_controller() -> Dictionary:
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	var br: BattleResolution = auto_free(BattleResolution.new())
	var bb: BondGaugeBurst = auto_free(BondGaugeBurst.new())
	br.setup(gb, tm)
	bb.setup(gb, tm, br)
	var ctrl: PlayerTurnController = auto_free(PlayerTurnController.new())
	ctrl.setup(tm, gb, br, bb)
	return {"gb": gb, "tm": tm, "br": br, "bb": bb, "ctrl": ctrl}

func test_unit_turn_started_crew_takes_control() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	ctx.ctrl._on_unit_turn_started(crew)
	assert_bool(ctx.ctrl.is_active()).is_true()
	assert_int(ctx.ctrl.get_current_unit_id()).is_equal(crew)
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)

func test_unit_turn_started_enemy_does_not_take_control() -> void:
	var ctx := _make_controller()
	var enemy := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 0))
	ctx.ctrl._on_unit_turn_started(enemy)
	assert_bool(ctx.ctrl.is_active()).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/player_turn_controller`
Expected: FAIL（解析错误：PlayerTurnController 不存在）。

- [ ] **Step 3: 最小实现**

```gdscript
# src/battle/player_turn_controller.gd
# 玩家回合输入控制器（Node）。严格先攻队列下，玩家 ACTIVE_TURN = 指挥当前被激活的 crew 单位。
# 本控制器不产生战斗逻辑：把输入翻译成对 GridBoard/BattleResolution/BondGaugeBurst/TurnManager 的调用。
# 逻辑（状态机+目标计算+派发）可单测；鼠标拾取/高亮/HUD 为视觉层（F5 验证）。
class_name PlayerTurnController
extends Node

enum Mode { IDLE, MOVE, ATTACK, BURST_LEAD, BURST_PARTNER }

var _turn_manager: TurnManager
var _grid_board: GridBoard
var _battle_resolution: BattleResolution
var _bond_gauge_burst: BondGaugeBurst
var _highlighter: Node = null   # BoardHighlighter（可空，测试不注入）
var _hud: Node = null           # BattleHUD（可空）

var _active: bool = false
var _current_unit_id: int = -1
var _mode: int = Mode.IDLE
var _valid_targets: Array[Vector2i] = []
var _burst_lead_id: int = -1

func setup(turn_manager: TurnManager, grid_board: GridBoard, battle_resolution: BattleResolution, bond_gauge_burst: BondGaugeBurst, highlighter: Node = null, hud: Node = null) -> void:
	_turn_manager = turn_manager
	_grid_board = grid_board
	_battle_resolution = battle_resolution
	_bond_gauge_burst = bond_gauge_burst
	_highlighter = highlighter
	_hud = hud
	if not EventBus.unit_turn_started.is_connected(_on_unit_turn_started):
		EventBus.unit_turn_started.connect(_on_unit_turn_started)
	if not EventBus.unit_turn_ended.is_connected(_on_unit_turn_ended):
		EventBus.unit_turn_ended.connect(_on_unit_turn_ended)
	if not EventBus.battle_won.is_connected(_on_battle_over):
		EventBus.battle_won.connect(_on_battle_over)
	if not EventBus.battle_lost.is_connected(_on_battle_over):
		EventBus.battle_lost.connect(_on_battle_over)

func _on_unit_turn_started(unit_id: int) -> void:
	_current_unit_id = unit_id
	var u: UnitInstance = _turn_manager.get_unit(unit_id)
	_active = u != null and u.definition.faction == "crew" and u.is_alive
	_burst_lead_id = -1
	_set_mode(Mode.IDLE)

func _on_unit_turn_ended(_unit_id: int) -> void:
	_active = false
	_set_mode(Mode.IDLE)

func _on_battle_over() -> void:
	_active = false
	_set_mode(Mode.IDLE)

func _set_mode(mode: int) -> void:
	_mode = mode
	_valid_targets = []
	if _highlighter != null:
		_highlighter.clear()

# ── 查询接口（供测试 + HUD）──
func is_active() -> bool:
	return _active

func get_mode() -> int:
	return _mode

func get_current_unit_id() -> int:
	return _current_unit_id

func get_valid_targets() -> Array[Vector2i]:
	return _valid_targets
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 的测试命令。Expected: PASS（2 测试）。

- [ ] **Step 5: 提交**（须用户授权）

```bash
git add src/battle/player_turn_controller.gd tests/unit/player_turn_controller/player_turn_controller_test.gd
git commit -m "feat(input): PlayerTurnController skeleton + turn ownership

Plan: docs/superpowers/plans/2026-06-20-player-turn-input-hud.md Task 2
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: MODE_MOVE — 可达格计算 + 移动执行

**Files:**
- Modify: `src/battle/player_turn_controller.gd`
- Test: `tests/unit/player_turn_controller/player_turn_controller_test.gd`（追加）

**Interfaces:**
- Consumes: `GridBoard.get_reachable_cells(pos, move_range) -> Array[Vector2i]`、`GridBoard.forced_move_unit(id, dest)`；`TurnManager.mark_has_moved(id)`；`UnitInstance.has_moved`、`.grid_position`、`.definition.move_range`。
- Produces: `set_mode(mode)`（公开）、`handle_cell_click(cell)`（公开）；MOVE 分支。

- [ ] **Step 1: 写失败测试**（追加到测试文件）

```gdscript
func test_set_mode_move_targets_are_reachable_cells() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	ctx.ctrl._on_unit_turn_started(crew)
	ctx.ctrl.set_mode(PlayerTurnController.Mode.MOVE)
	var expected := ctx.gb.get_reachable_cells(Vector2i(3, 7), 3)
	assert_array(ctx.ctrl.get_valid_targets()).is_equal(expected)
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.MOVE)

func test_handle_cell_click_move_relocates_unit_and_marks_moved() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	ctx.ctrl._on_unit_turn_started(crew)
	ctx.ctrl.set_mode(PlayerTurnController.Mode.MOVE)
	var dest := Vector2i(3, 6)
	ctx.ctrl.handle_cell_click(dest)
	var u: UnitInstance = ctx.tm.get_unit(crew)
	assert_vector(u.grid_position).is_equal(dest)
	assert_bool(u.has_moved).is_true()
	assert_int(ctx.gb.get_unit_pos(crew).x).is_equal(3)
	assert_int(ctx.gb.get_unit_pos(crew).y).is_equal(6)
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)

func test_handle_cell_click_illegal_cell_no_effect() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	ctx.ctrl._on_unit_turn_started(crew)
	ctx.ctrl.set_mode(PlayerTurnController.Mode.MOVE)
	ctx.ctrl.handle_cell_click(Vector2i(0, 0))  # 越出 move_range=3 的可达集
	var u: UnitInstance = ctx.tm.get_unit(crew)
	assert_vector(u.grid_position).is_equal(Vector2i(3, 7))
	assert_bool(u.has_moved).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/player_turn_controller`
Expected: FAIL（set_mode/handle_cell_click 未定义）。

- [ ] **Step 3: 实现**

在 `player_turn_controller.gd` 加（替换 `_set_mode` 为公开 `set_mode` 调度 + 新增 `handle_cell_click` 与 MOVE 分支）。把原 `_set_mode` 保留为内部清理，新增公开 `set_mode`：

```gdscript
# 公开：进入模式 → 计算合法目标 → 高亮。
func set_mode(mode: int) -> void:
	if not _active:
		return
	_mode = mode
	_valid_targets = _compute_targets(mode)
	if _highlighter != null:
		if _valid_targets.is_empty():
			_highlighter.clear()
		else:
			_highlighter.show_cells(_valid_targets, _color_for(mode))

func cancel() -> void:
	_set_mode(Mode.IDLE)

func handle_cell_click(cell: Vector2i) -> void:
	if not _active:
		return
	if not cell in _valid_targets:
		return
	match _mode:
		Mode.MOVE:
			_do_move(cell)

func _compute_targets(mode: int) -> Array[Vector2i]:
	var u: UnitInstance = _turn_manager.get_unit(_current_unit_id)
	if u == null:
		return []
	match mode:
		Mode.MOVE:
			if u.has_moved:
				return []
			return _grid_board.get_reachable_cells(u.grid_position, u.definition.move_range)
		_:
			return []

func _do_move(cell: Vector2i) -> void:
	_grid_board.forced_move_unit(_current_unit_id, cell)
	_turn_manager.get_unit(_current_unit_id).grid_position = cell
	_turn_manager.mark_has_moved(_current_unit_id)
	_set_mode(Mode.IDLE)

func _color_for(mode: int) -> Color:
	match mode:
		Mode.MOVE: return Color("#22FF66")
		Mode.ATTACK: return Color("#FF2222")
		_: return Color("#FFCC00")
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS（含前序共 5 测试）。

- [ ] **Step 5: 提交**（须用户授权）

```bash
git add src/battle/player_turn_controller.gd tests/unit/player_turn_controller/player_turn_controller_test.gd
git commit -m "feat(input): MODE_MOVE reachable-cell targeting + move execution

Plan: docs/superpowers/plans/2026-06-20-player-turn-input-hud.md Task 3
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: MODE_ATTACK — 射程内敌人 + 普攻执行

**Files:**
- Modify: `src/battle/player_turn_controller.gd`
- Test: `tests/unit/player_turn_controller/player_turn_controller_test.gd`（追加）

**Interfaces:**
- Consumes: `TurnManager.get_alive_enemies() -> Array[int]`；`BattleResolution.is_valid_attack(attacker, target) -> bool`、`execute_attack(attacker, target)`（内部 mark_has_acted + emit damage_dealt）；`UnitInstance.has_acted`。
- Produces: ATTACK 分支于 `_compute_targets` 与 `handle_cell_click`；辅助 `_enemy_at(cell) -> int`。

- [ ] **Step 1: 写失败测试**（追加）

```gdscript
func test_set_mode_attack_targets_are_in_range_enemies() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 6))
	var enemy := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))
	ctx.ctrl._on_unit_turn_started(crew)
	ctx.ctrl.set_mode(PlayerTurnController.Mode.ATTACK)
	assert_array(ctx.ctrl.get_valid_targets()).contains([Vector2i(3, 5)])

func test_handle_cell_click_attack_damages_enemy() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 6))
	var enemy := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))
	ctx.ctrl._on_unit_turn_started(crew)
	ctx.ctrl.set_mode(PlayerTurnController.Mode.ATTACK)
	ctx.ctrl.handle_cell_click(Vector2i(3, 5))
	var e: UnitInstance = ctx.tm.get_unit(enemy)
	assert_int(e.current_hp).is_equal(3)  # 6 - base_damage 3
	var c: UnitInstance = ctx.tm.get_unit(crew)
	assert_bool(c.has_acted).is_true()
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)
```

- [ ] **Step 2: 跑测试确认失败**

Run: 同 Task 3 Step 2。Expected: FAIL（ATTACK 分支缺失 → valid_targets 空 / 未掉血）。

- [ ] **Step 3: 实现**

在 `_compute_targets` 的 match 加 ATTACK 分支；`handle_cell_click` 的 match 加 ATTACK；新增 `_enemy_at`、`_do_attack`：

```gdscript
		Mode.ATTACK:
			if u.has_acted:
				return []
			var cells: Array[Vector2i] = []
			for eid in _turn_manager.get_alive_enemies():
				if _battle_resolution.is_valid_attack(_current_unit_id, eid):
					cells.append(_turn_manager.get_unit(eid).grid_position)
			return cells
```

```gdscript
		Mode.ATTACK:
			_do_attack(cell)
```

```gdscript
func _enemy_at(cell: Vector2i) -> int:
	for eid in _turn_manager.get_alive_enemies():
		if _turn_manager.get_unit(eid).grid_position == cell:
			return eid
	return -1

func _do_attack(cell: Vector2i) -> void:
	var target := _enemy_at(cell)
	if target == -1:
		return
	_battle_resolution.execute_attack(_current_unit_id, target)
	_set_mode(Mode.IDLE)
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: 提交**（须用户授权）

```bash
git add src/battle/player_turn_controller.gd tests/unit/player_turn_controller/player_turn_controller_test.gd
git commit -m "feat(input): MODE_ATTACK in-range targeting + attack execution

Plan: docs/superpowers/plans/2026-06-20-player-turn-input-hud.md Task 4
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 职业动词 — slash / guard 立即执行

**Files:**
- Modify: `src/battle/player_turn_controller.gd`
- Test: `tests/unit/player_turn_controller/player_turn_controller_test.gd`（追加）

**Interfaces:**
- Consumes: `BattleResolution.execute_slash(attacker)`（相邻敌 AoE，内部 mark_has_used_verb）、`execute_guard(caster, target)`（内部 mark_has_used_verb + apply GUARDED）；`UnitInstance.definition.class_action_id`、`.has_used_verb`。
- Produces: `do_verb() -> void`（公开，HUD[动词]按钮调用）。

- [ ] **Step 1: 写失败测试**（追加）

```gdscript
func test_do_verb_slash_hits_adjacent_enemy_and_marks_verb() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 6))
	var enemy := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))
	ctx.ctrl._on_unit_turn_started(crew)
	ctx.ctrl.do_verb()
	assert_bool(ctx.tm.get_unit(crew).has_used_verb).is_true()
	assert_int(ctx.tm.get_unit(enemy).current_hp).is_equal(3)  # 相邻被斩，base 3

func test_do_verb_guard_marks_self_guarded() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "bulwark", 2, 2, 12, "guard"), Vector2i(3, 6))
	ctx.ctrl._on_unit_turn_started(crew)
	ctx.ctrl.do_verb()
	assert_bool(ctx.tm.get_unit(crew).has_used_verb).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: 同 Task 3 Step 2。Expected: FAIL（do_verb 未定义）。

- [ ] **Step 3: 实现**

```gdscript
# HUD[动词]按钮调用。无目标动词（slash/guard/aura）立即执行；需目标的动词留 MVP 后续 story。
func do_verb() -> void:
	if not _active:
		return
	var u: UnitInstance = _turn_manager.get_unit(_current_unit_id)
	if u == null or u.has_used_verb or u.definition.class_action_id == "":
		return
	match u.definition.class_action_id:
		"slash":
			_battle_resolution.execute_slash(_current_unit_id)
		"guard":
			_battle_resolution.execute_guard(_current_unit_id, _current_unit_id)
		_:
			push_warning("PlayerTurnController.do_verb: MVP 未支持动词 %s（cannon/heal/displace 需目标选择，留后续 story）" % u.definition.class_action_id)
			return
	_set_mode(Mode.IDLE)
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: 提交**（须用户授权）

```bash
git add src/battle/player_turn_controller.gd tests/unit/player_turn_controller/player_turn_controller_test.gd
git commit -m "feat(input): class verb (slash/guard) immediate execution

Plan: docs/superpowers/plans/2026-06-20-player-turn-input-hud.md Task 5
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 爆发 — lead/partner 选择 + 激活

**Files:**
- Modify: `src/battle/player_turn_controller.gd`
- Test: `tests/unit/player_turn_controller/player_turn_controller_test.gd`（追加）

**Interfaces:**
- Consumes: `BondGaugeBurst.is_full() -> bool`、`can_activate_burst(lead, partner) -> bool`、`activate_burst(lead, partner) -> bool`；`TurnManager.get_alive_allies()`；`GridBoard.chebyshev(a, b)`（静态）；`UnitInstance.has_acted`、`.has_used_verb`、`.is_alive`、`.grid_position`。
- Produces: BURST_LEAD/BURST_PARTNER 分支；`begin_burst_targeting()`（公开，HUD[爆发]按钮调用）；`_ally_at(cell)`。
- 测试前置：需让 `_bond_gauge_burst.is_full()` 为真。BondGaugeBurst 充能内核公开 `apply_attack_charge` 等；最简用反复 `apply_received_charge` 充满，或直接 `bb.apply_attack_charge(true)` 多次。本测试用循环充满到 10。

- [ ] **Step 1: 写失败测试**（追加）

```gdscript
func _fill_gauge(bb: BondGaugeBurst) -> void:
	# 反复相邻攻击充能（+2/次）直到满；apply_attack_charge(has_adjacent_ally:=true)
	for i in 10:
		bb.apply_attack_charge(true)

func test_begin_burst_targeting_highlights_eligible_leads() -> void:
	var ctx := _make_controller()
	var lead := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	var partner := _register(ctx.tm, ctx.gb, _make_def("crew", "bulwark", 2, 2, 12, "guard"), Vector2i(3, 6))
	_fill_gauge(ctx.bb)
	ctx.ctrl._on_unit_turn_started(lead)
	ctx.ctrl.begin_burst_targeting()
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.BURST_LEAD)
	# lead/partner 均存活未行动 → 都是合法 lead
	assert_array(ctx.ctrl.get_valid_targets()).contains([Vector2i(3, 7), Vector2i(3, 6)])

func test_burst_lead_then_partner_activates_burst() -> void:
	var ctx := _make_controller()
	var lead := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	var partner := _register(ctx.tm, ctx.gb, _make_def("crew", "bulwark", 2, 2, 12, "guard"), Vector2i(3, 6))
	var enemy := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))
	_fill_gauge(ctx.bb)
	ctx.ctrl._on_unit_turn_started(lead)
	ctx.ctrl.begin_burst_targeting()
	ctx.ctrl.handle_cell_click(Vector2i(3, 7))   # 选 lead = swordsman
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.BURST_PARTNER)
	ctx.ctrl.handle_cell_click(Vector2i(3, 6))   # 选 partner = bulwark（破阵先锋）
	# 破阵先锋：铁壁 GUARDED + 剑豪穿透斩（×2=6）命中相邻敌 → 敌 6hp 归零
	assert_bool(ctx.bb.is_full()).is_false()      # 槽已清零
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)
```

- [ ] **Step 2: 跑测试确认失败**

Run: 同 Task 3 Step 2。Expected: FAIL（begin_burst_targeting 未定义）。

- [ ] **Step 3: 实现**

`_compute_targets` 加 BURST 分支；`handle_cell_click` 加 BURST 分支；新增 `begin_burst_targeting`、`_ally_at`、`_select_burst_lead`、`_do_burst`：

```gdscript
		Mode.BURST_LEAD:
			var leads: Array[Vector2i] = []
			for aid in _turn_manager.get_alive_allies():
				var a: UnitInstance = _turn_manager.get_unit(aid)
				if a.is_alive and not a.has_acted:
					leads.append(a.grid_position)
			return leads
		Mode.BURST_PARTNER:
			var partners: Array[Vector2i] = []
			if _burst_lead_id == -1:
				return partners
			var lead_pos := _turn_manager.get_unit(_burst_lead_id).grid_position
			for aid in _turn_manager.get_alive_allies():
				if aid == _burst_lead_id:
					continue
				var a: UnitInstance = _turn_manager.get_unit(aid)
				if a.is_alive and not a.has_used_verb and GridBoard.chebyshev(lead_pos, a.grid_position) == 1:
					partners.append(a.grid_position)
			return partners
```

```gdscript
		Mode.BURST_LEAD:
			_select_burst_lead(cell)
		Mode.BURST_PARTNER:
			_do_burst(cell)
```

```gdscript
# HUD[爆发]按钮调用（仅槽满时按钮可点）。
func begin_burst_targeting() -> void:
	if not _active or not _bond_gauge_burst.is_full():
		return
	_burst_lead_id = -1
	set_mode(Mode.BURST_LEAD)

func _ally_at(cell: Vector2i) -> int:
	for aid in _turn_manager.get_alive_allies():
		if _turn_manager.get_unit(aid).grid_position == cell:
			return aid
	return -1

func _select_burst_lead(cell: Vector2i) -> void:
	var lead := _ally_at(cell)
	if lead == -1:
		return
	_burst_lead_id = lead
	set_mode(Mode.BURST_PARTNER)

func _do_burst(cell: Vector2i) -> void:
	var partner := _ally_at(cell)
	if partner == -1 or _burst_lead_id == -1:
		return
	_bond_gauge_burst.activate_burst(_burst_lead_id, partner)
	_burst_lead_id = -1
	_set_mode(Mode.IDLE)
```

注：`set_mode(Mode.BURST_LEAD/PARTNER)` 复用现有公开 `set_mode`（会算目标+高亮金色）。`_color_for` 已对非 MOVE/ATTACK 回退金色。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS。若 `apply_attack_charge` 签名不符，查 `src/battle/bond_gauge_burst.gd` 充能公共方法名并对齐 `_fill_gauge`。

- [ ] **Step 5: 提交**（须用户授权）

```bash
git add src/battle/player_turn_controller.gd tests/unit/player_turn_controller/player_turn_controller_test.gd
git commit -m "feat(input): burst lead/partner targeting + activation

Plan: docs/superpowers/plans/2026-06-20-player-turn-input-hud.md Task 6
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: get_available_actions + end_turn

**Files:**
- Modify: `src/battle/player_turn_controller.gd`
- Test: `tests/unit/player_turn_controller/player_turn_controller_test.gd`（追加）

**Interfaces:**
- Consumes: `TurnManager.end_current_turn()`；`UnitInstance.has_moved/has_acted/has_used_verb`。
- Produces: `get_available_actions() -> Dictionary`（keys: move/attack/verb/burst → bool）、`end_turn() -> void`。

- [ ] **Step 1: 写失败测试**（追加）

```gdscript
func test_get_available_actions_reflects_flags() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 6))
	var enemy := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))
	ctx.ctrl._on_unit_turn_started(crew)
	var a := ctx.ctrl.get_available_actions()
	assert_bool(a["move"]).is_true()
	assert_bool(a["attack"]).is_true()    # 相邻敌可攻
	assert_bool(a["verb"]).is_true()      # 有 slash
	assert_bool(a["burst"]).is_false()    # 槽未满
	# 攻击后 attack 关闭
	ctx.ctrl.set_mode(PlayerTurnController.Mode.ATTACK)
	ctx.ctrl.handle_cell_click(Vector2i(3, 5))
	assert_bool(ctx.ctrl.get_available_actions()["attack"]).is_false()

func test_end_turn_delegates_to_turn_manager() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 6))
	var enemy := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 0))
	ctx.tm.start_battle()
	# 当前应是某单位 ACTIVE_TURN；让控制器接管当前单位后结束
	var cur := ctx.tm.get_current_unit_id()
	ctx.ctrl._on_unit_turn_started(cur)
	ctx.ctrl.end_turn()
	# 结束后当前单位应推进（不再是 cur，或进入下一状态）
	assert_int(ctx.tm.get_current_unit_id()).is_not_equal(cur)
```

- [ ] **Step 2: 跑测试确认失败**

Run: 同 Task 3 Step 2。Expected: FAIL（get_available_actions/end_turn 未定义）。

- [ ] **Step 3: 实现**

```gdscript
func get_available_actions() -> Dictionary:
	var result := {"move": false, "attack": false, "verb": false, "burst": false}
	if not _active:
		return result
	var u: UnitInstance = _turn_manager.get_unit(_current_unit_id)
	if u == null:
		return result
	result["move"] = not u.has_moved and not _grid_board.get_reachable_cells(u.grid_position, u.definition.move_range).is_empty()
	if not u.has_acted:
		for eid in _turn_manager.get_alive_enemies():
			if _battle_resolution.is_valid_attack(_current_unit_id, eid):
				result["attack"] = true
				break
	result["verb"] = not u.has_used_verb and u.definition.class_action_id in ["slash", "guard"]
	result["burst"] = _bond_gauge_burst.is_full()
	return result

func end_turn() -> void:
	if not _active:
		return
	_set_mode(Mode.IDLE)
	_turn_manager.end_current_turn()
```

- [ ] **Step 4: 跑测试确认通过 + 全量回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit -a res://tests/integration`
Expected: 全 PASS（含既有 228 + 新增控制器测试）。

- [ ] **Step 5: 提交**（须用户授权）

```bash
git add src/battle/player_turn_controller.gd tests/unit/player_turn_controller/player_turn_controller_test.gd
git commit -m "feat(input): available-action query + end_turn delegation

Plan: docs/superpowers/plans/2026-06-20-player-turn-input-hud.md Task 7
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: BoardHighlighter（纯视觉节点）

**Files:**
- Create: `src/board/board_highlighter.gd`
- Test: `tests/unit/board_highlighter/board_highlighter_test.gd`（仅实例化+API 冒烟，渲染走 F5）

**Interfaces:**
- Consumes: `GridCoordMapper.grid_to_world(cell)`。
- Produces: `class_name BoardHighlighter extends Node3D`；`show_cells(cells: Array[Vector2i], color: Color) -> void`、`clear() -> void`。

- [ ] **Step 1: 写冒烟测试**

```gdscript
# tests/unit/board_highlighter/board_highlighter_test.gd
extends GdUnitTestSuite

func test_show_then_clear_does_not_crash() -> void:
	var bh: BoardHighlighter = auto_free(BoardHighlighter.new())
	add_child(bh)
	bh.show_cells([Vector2i(0, 0), Vector2i(1, 1)], Color("#22FF66"))
	bh.clear()
	assert_object(bh).is_not_null()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/board_highlighter`
Expected: FAIL（BoardHighlighter 不存在）。

- [ ] **Step 3: 实现**

```gdscript
# src/board/board_highlighter.gd
# 棋盘格高亮（Node3D，ADR-0006 高亮规范）。MeshInstance3D 池，y=0.01 防 z-fighting。纯视觉，零逻辑。
class_name BoardHighlighter
extends Node3D

const HIGHLIGHT_Y: float = 0.01

var _pool: Array[MeshInstance3D] = []

func show_cells(cells: Array[Vector2i], color: Color) -> void:
	clear()
	_ensure_pool(cells.size())
	for i in cells.size():
		var hl := _pool[i]
		var mat := hl.material_override as StandardMaterial3D
		mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
		var world := GridCoordMapper.grid_to_world(cells[i])
		hl.position = Vector3(world.x, HIGHLIGHT_Y, world.z)
		hl.visible = true

func clear() -> void:
	for hl in _pool:
		hl.visible = false

func _ensure_pool(n: int) -> void:
	while _pool.size() < n:
		var hl := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(GridCoordMapper.CELL_SIZE * 0.92, GridCoordMapper.CELL_SIZE * 0.92)
		hl.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hl.material_override = mat
		hl.visible = false
		add_child(hl)
		_pool.append(hl)
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: 提交**（须用户授权）

```bash
git add src/board/board_highlighter.gd tests/unit/board_highlighter/board_highlighter_test.gd
git commit -m "feat(board): BoardHighlighter cell-highlight pool (ADR-0006)

Plan: docs/superpowers/plans/2026-06-20-player-turn-input-hud.md Task 8
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: BattleHUD（纯视觉 Control）

**Files:**
- Create: `src/ui/battle_hud.gd`
- Test: 无自动化测试（纯 UI，ADVISORY；F5 验证）。本任务交付物在 Task 11 集成后目视。

**Interfaces:**
- Consumes: `PlayerTurnController.set_mode/do_verb/begin_burst_targeting/end_turn/get_available_actions/get_current_unit_id`；`TurnManager.get_unit(id)`；EventBus 显示信号。
- Produces: `class_name BattleHUD extends Control`；`setup(controller: PlayerTurnController, turn_manager: TurnManager) -> void`；`refresh() -> void`。

- [ ] **Step 1: 实现（无 TDD，纯视觉）**

```gdscript
# src/ui/battle_hud.gd
# 白盒战斗 HUD（Control，挂 HUDLayer CanvasLayer layer=5）。零美术：Button/Label/ColorRect 拼装。
# 只读显示 + 把按钮点击转交 PlayerTurnController。
class_name BattleHUD
extends Control

var _controller: PlayerTurnController
var _turn_manager: TurnManager

var _info_label: Label
var _gauge_label: Label
var _round_label: Label
var _btn_move: Button
var _btn_attack: Button
var _btn_verb: Button
var _btn_burst: Button
var _btn_end: Button

func setup(controller: PlayerTurnController, turn_manager: TurnManager) -> void:
	_controller = controller
	_turn_manager = turn_manager
	_build_ui()
	for sig in ["unit_turn_started", "unit_turn_ended", "damage_dealt", "heal_executed",
			"gauge_charged", "bond_gauge_full", "burst_executed", "round_started", "last_round_warning"]:
		EventBus.connect(sig, _on_any_change)
	refresh()

func _on_any_change(_a = null, _b = null, _c = null) -> void:
	refresh()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_round_label = Label.new()
	_round_label.position = Vector2(20, 16)
	add_child(_round_label)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.position = Vector2(20, -56)
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)

	_info_label = Label.new()
	_info_label.custom_minimum_size = Vector2(220, 0)
	bar.add_child(_info_label)

	_btn_move = _make_button("移动", func() -> void: _controller.set_mode(PlayerTurnController.Mode.MOVE))
	_btn_attack = _make_button("攻击", func() -> void: _controller.set_mode(PlayerTurnController.Mode.ATTACK))
	_btn_verb = _make_button("动词", func() -> void: _controller.do_verb(); refresh())
	_btn_burst = _make_button("爆发", func() -> void: _controller.begin_burst_targeting())
	_btn_end = _make_button("结束回合", func() -> void: _controller.end_turn())
	for b in [_btn_move, _btn_attack, _btn_verb, _btn_burst, _btn_end]:
		bar.add_child(b)

	_gauge_label = Label.new()
	bar.add_child(_gauge_label)

func _make_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b

func refresh() -> void:
	if _controller == null:
		return
	_round_label.text = "第 %d 轮 / 8" % _turn_manager.get_current_round()
	var actions := _controller.get_available_actions()
	_btn_move.disabled = not actions["move"]
	_btn_attack.disabled = not actions["attack"]
	_btn_verb.disabled = not actions["verb"]
	_btn_burst.disabled = not actions["burst"]
	_btn_burst.modulate = Color("#FFCC00") if actions["burst"] else Color.WHITE
	_btn_end.disabled = not _controller.is_active()
	if _controller.is_active():
		var u: UnitInstance = _turn_manager.get_unit(_controller.get_current_unit_id())
		_info_label.text = "%s  HP %d/%d  [移%s 攻%s 词%s]" % [
			u.definition.display_name, u.current_hp, u.definition.max_hp,
			"✓" if u.has_moved else "·", "✓" if u.has_acted else "·", "✓" if u.has_used_verb else "·"]
	else:
		_info_label.text = "敌方回合…"
```

注：`get_current_round()` 是 TurnManager 既有方法（turn_manager.gd:158）。EventBus.connect 用字符串名 + 变参回调 `_on_any_change`（信号参数数量不一，用默认参兜底）。

- [ ] **Step 2: 编译校验（导入零错）**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo OK`
Expected: OK（无解析错误）。

- [ ] **Step 3: 提交**（须用户授权）

```bash
git add src/ui/battle_hud.gd
git commit -m "feat(ui): whitebox BattleHUD action bar + status (no art)

Plan: docs/superpowers/plans/2026-06-20-player-turn-input-hud.md Task 9
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: UnitView 头顶 HP + UnitRenderer 订阅

**Files:**
- Modify: `src/render/unit_view.gd`
- Modify: `src/render/unit_renderer.gd`
- Test: 无自动化（纯视觉，F5 验证）。

**Interfaces:**
- Consumes: `EventBus.damage_dealt(target_id, final_damage, new_hp)`、`heal_executed(target_id, amount)`。
- Produces: `UnitView.set_hp(current: int, max_hp: int) -> void`（新增 Label3D 显示）。

- [ ] **Step 1: 实现 UnitView.set_hp**

在 `src/render/unit_view.gd` 的 `setup` 末尾建 Label3D，并加 `set_hp`：

```gdscript
# 在类成员区加：
var _hp_label: Label3D

# 在 setup() 末尾（global_position 设置之后）追加：
	_hp_label = Label3D.new()
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	_hp_label.fixed_size = true
	_hp_label.pixel_size = 0.008
	_hp_label.position = Vector3(0, 1.9, 0)
	_hp_label.modulate = Color.WHITE
	add_child(_hp_label)

# 新增方法：
func set_hp(current: int, max_hp: int) -> void:
	if _hp_label != null:
		_hp_label.text = "%d/%d" % [current, max_hp]
```

- [ ] **Step 2: UnitRenderer 订阅 damage/heal 更新 HP**

在 `src/render/unit_renderer.gd` 的 `_ready` 加订阅，并在 `spawn_view` 后初始化满血。改 `spawn_view` 增加 max_hp 参数会牵动 battle_scene；改为：spawn 时不知 HP，由 BattleScene 在 spawn 后调 `view.set_hp(...)`（Task 11 接线）。本任务只加 damage/heal 订阅：

```gdscript
# _ready() 内追加：
	if not EventBus.damage_dealt.is_connected(_on_hp_changed):
		EventBus.damage_dealt.connect(_on_hp_changed)
	if not EventBus.heal_executed.is_connected(_on_heal):
		EventBus.heal_executed.connect(_on_heal)

# 新增（damage_dealt 第三参 new_hp 直接给）：
func _on_hp_changed(target_id: int, _final_damage: int, new_hp: int) -> void:
	var v: UnitView = _views.get(target_id, null)
	if v != null:
		v.set_hp(new_hp, _max_hp.get(target_id, new_hp))

func _on_heal(target_id: int, _amount: int) -> void:
	pass  # heal_executed 不带 new_hp；HP 文本在下次 damage 或由 BattleScene 主动刷新（MVP 简化）

# 加成员缓存 max_hp（spawn 时由 BattleScene 写入）：
var _max_hp: Dictionary = {}
func set_unit_max_hp(battle_id: int, max_hp: int) -> void:
	_max_hp[battle_id] = max_hp
```

注：heal_executed 信号只带 (target_id, amount)（EventBus 定义），不含 new_hp。MVP 治疗后 HP 文本不即时更新血量（下次受伤刷新），可接受；若需精确，后续 story 让 BattleScene 在 heal 后查 UnitInstance.current_hp 刷新。

- [ ] **Step 3: 编译校验**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo OK`
Expected: OK。

- [ ] **Step 4: 提交**（须用户授权）

```bash
git add src/render/unit_view.gd src/render/unit_renderer.gd
git commit -m "feat(render): UnitView overhead HP Label3D + renderer HP subscription

Plan: docs/superpowers/plans/2026-06-20-player-turn-input-hud.md Task 10
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: 集成进 BattleScene + F5 验证

**Files:**
- Modify: `scenes/BattleScene.tscn`
- Modify: `src/battle/battle_scene.gd`
- Test: 既有 `tests/integration/battle/full_battle_test.gd` 回归 + F5 手动核对。

**Interfaces:**
- Consumes: 所有前序产出。
- Produces: 可 F5 操作的战斗。

- [ ] **Step 1: 在 BattleScene.tscn 加节点**

`scenes/BattleScene.tscn` 加三个 ext_resource 与节点（在既有节点后；BattleHUD 挂 HUDLayer 下）：

```
[ext_resource type="Script" path="res://src/battle/player_turn_controller.gd" id="11_ptc"]
[ext_resource type="Script" path="res://src/board/board_highlighter.gd" id="12_bh"]
[ext_resource type="Script" path="res://src/ui/battle_hud.gd" id="13_hud"]
```

```
[node name="PlayerTurnController" type="Node" parent="."]
script = ExtResource("11_ptc")

[node name="BoardHighlighter" type="Node3D" parent="."]
script = ExtResource("12_bh")

[node name="BattleHUD" type="Control" parent="HUDLayer"]
script = ExtResource("13_hud")
```

（load_steps 计数相应 +3。）

- [ ] **Step 2: battle_scene.gd 接线**

在 `src/battle/battle_scene.gd` 加 @onready 引用，并在 `_spawn_all_views()` 写入 max_hp、在 `_ready()` setup 序列接线控制器+HUD：

```gdscript
@onready var _board_highlighter: BoardHighlighter = $BoardHighlighter
@onready var _player_turn_controller: PlayerTurnController = $PlayerTurnController
@onready var _battle_hud: BattleHUD = $HUDLayer/BattleHUD
```

在 `_ready()` 内、`_turn_manager.start_battle()` **之前**接线：

```gdscript
	_player_turn_controller.setup(_turn_manager, _grid_board, _battle_resolution, _bond_gauge_burst, _board_highlighter, _battle_hud)
	_battle_hud.setup(_player_turn_controller, _turn_manager)
```

`_spawn_all_views()` 内每个 view 之后写 max_hp：

```gdscript
		var view := _unit_renderer.spawn_view(inst.definition.unit_class, inst.definition.faction, battle_id, inst.grid_position)
		_unit_renderer.set_unit_max_hp(battle_id, inst.definition.max_hp)
		view.set_hp(inst.current_hp, inst.definition.max_hp)
```

（注：`spawn_view` 已返回 UnitView。）

- [ ] **Step 3: 控制器加鼠标拾取 + Esc（视觉壳，F5 验证）**

在 `src/battle/player_turn_controller.gd` 加 `_unhandled_input` 与射线拾取（非物理，遵 ADR-0007）。
HUD 按钮属 GUI 输入，会被 Godot 先消费，不进 `_unhandled_input`，故格点击与按钮点击不冲突：

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _screen_to_cell(event.position)
		if cell != Vector2i(-1, -1):
			handle_cell_click(cell)

# 鼠标屏幕坐标 → 与 y=0 棋盘平面求交 → 逻辑格（非物理拾取）。
func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2i(-1, -1)
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector2i(-1, -1)
	var t := -from.y / dir.y
	if t < 0.0:
		return Vector2i(-1, -1)
	var world := from + dir * t
	var cell := GridCoordMapper.world_to_grid(world)
	if not GridCoordMapper.in_bounds(cell):
		return Vector2i(-1, -1)
	return cell
```

注：输入锁（burst presentation 期间忽略输入）本 MVP 暂不接——演出层仍 stub、不发 started/ended，`_locked` 恒 false 属死代码（YAGNI）；爆发演出 story 落地时再补订阅。

- [ ] **Step 4: 导入 + 全量回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit -a res://tests/integration`
Expected: 全 PASS。`full_battle_test` 仍停在首个玩家 ACTIVE_TURN（控制器接管不自动结束回合，状态不变）。

- [ ] **Step 5: F5 手动验收（ADVISORY，交用户目视签字）**

用户 F5，逐条核对 spec 验收标准：
- AC-1：阿斩回合动作栏按可用行动点启用；敌方回合显示"敌方回合"、动作栏禁用。
- AC-2：点[移动]→绿格→点格→单位补间移动、[移动]灰。
- AC-3：点[攻击]→红格→点敌→掉血（头顶 HP 变）、[攻击]灰。
- AC-4：点[动词]→阿斩斩相邻敌/铁壁自挡、[动词]灰。
- AC-5：槽满（多打几拳）→[爆发]金→点→选 lead→选 partner→爆发生效。
- AC-6：[结束回合]→推进；敌方自动行动后回到下一玩家单位。
- AC-7：Esc 取消模式、清高亮。
- AC-8：敌方移动也有补间。

- [ ] **Step 6: 提交**（须用户授权）

```bash
git add scenes/BattleScene.tscn src/battle/battle_scene.gd
git commit -m "feat(battle): wire player input + HUD + highlighter into BattleScene

Plan: docs/superpowers/plans/2026-06-20-player-turn-input-hud.md Task 11
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## 实现顺序与依赖
Task 1（unit_moved）→ 2（骨架）→ 3/4/5/6/7（控制器各能力，顺序推进）→ 8（highlighter）/9（HUD）/10（HP）可并行 → 11（集成+F5）。
逻辑 BLOCKING（1-7）全绿后再做视觉（8-11）；视觉只能 F5 验证，须用户签字。

## 风险与回退
- **Task 1 改 forced_move_unit 可能影响 EnemyAI 执行测试**：若回归红，检查是否有测试隐式断言 unit_moved 未发；调整为断言行为而非信号缺席。
- **`apply_attack_charge` 充能方法名**：Task 6 `_fill_gauge` 依赖之；若名不符，查 bond_gauge_burst.gd 公共充能 API 对齐。
- **BattleHUD EventBus.connect 变参回调**：Godot 4.6 信号参数数不一，用带默认参的 `_on_any_change` 兜底；若个别信号参数超 3 个导致连接报错，单独为该信号写专用 handler。
