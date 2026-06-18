# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: 完整核心循环 部署→移动凑相邻→普攻充能→相邻爆发→清场 在 Godot 落地
# Date: 2026-06-18
#
# 战斗主编排器（挂在 Main.tscn 根 Node3D）。代码构建场景树（最小化 .tscn 手写）。
# 协调 GridBoard / UnitLayer / BondSystem / TurnManager / EnemyAI / BurstPresentation。
extends Node3D

const UnitLayerScript = preload("res://src/systems/board/unit_layer.gd")
const BurstPresentationScript = preload("res://src/presentation/burst_presentation.gd")

var _camera: Camera3D
var _unit_layer: UnitLayer
var _highlight_root: Node3D
var _burst: BurstPresentation

var _board: GridBoard
var _bond: BondSystem
var _turn: TurnManager

var _units: Dictionary = {}            # int instance_id -> UnitInstance
var _next_id: int = 1

# 输入状态
enum Mode { NORMAL, BURST_SELECT }
var _mode: int = Mode.NORMAL
var _selected_id: int = -1
var _burst_lead_id: int = -1
var _input_locked: bool = false
var _highlights: Array[MeshInstance3D] = []

# HUD
var _hud: CanvasLayer
var _gauge_label: Label
var _round_label: Label
var _info_label: Label
var _intent_label: Label
var _end_turn_btn: Button
var _burst_btn: Button

func _ready() -> void:
	_board = GridBoard.new()
	_bond = BondSystem.new()
	_turn = TurnManager.new()

	_build_camera()
	_build_board_visuals()
	_build_highlight_root()
	_build_unit_layer()
	_build_burst_layer()
	_build_hud()

	_connect_events()
	_spawn_units()

	EventBus.battle_started.emit()
	_turn.set_state(TurnManager.BattleState.PLAYER_PHASE)
	_refresh_hud()

# ─────────────────────────── 场景构建 ───────────────────────────

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 60.0
	_camera.position = Vector3(7.0, 16.0, 22.0)
	add_child(_camera)
	_camera.look_at(GridCoordMapper.board_center(), Vector3.UP)

	# 简单光照
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0E1A2A")   # 海蓝灰底（art-bible §2 战斗）
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#33445A")
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

func _build_board_visuals() -> void:
	var n: int = SliceConfig.BOARD_SIZE
	var size: float = n * SliceConfig.CELL_SIZE
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)        # 法线默认 +Y（ADR-0006，不旋转）
	plane.mesh = pm
	var c := (n - 1) / 2.0 * SliceConfig.CELL_SIZE
	plane.position = Vector3(c, -0.01, c)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#16283C")
	plane.material_override = mat
	add_child(plane)

	# 格线（每格描边的细方块）
	for col in n:
		for row in n:
			var tile := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(SliceConfig.CELL_SIZE * 0.92, 0.05, SliceConfig.CELL_SIZE * 0.92)
			tile.mesh = tm
			tile.position = GridCoordMapper.grid_to_world(Vector2i(col, row))
			var tmat := StandardMaterial3D.new()
			# 棋盘格交错明暗
			tmat.albedo_color = Color("#1E3450") if (col + row) % 2 == 0 else Color("#24405E")
			tile.material_override = tmat
			add_child(tile)

func _build_highlight_root() -> void:
	_highlight_root = Node3D.new()
	add_child(_highlight_root)

func _build_unit_layer() -> void:
	_unit_layer = UnitLayerScript.new()
	add_child(_unit_layer)

func _build_burst_layer() -> void:
	_burst = BurstPresentationScript.new()
	add_child(_burst)
	_burst.setup(_camera)

# ─────────────────────────── HUD ───────────────────────────

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)

	_round_label = _make_label(Vector2(16, 16), 22, Color("#FFFFFF"))
	_gauge_label = _make_label(Vector2(16, 48), 24, Color("#FFCC00"))
	_intent_label = _make_label(Vector2(16, 84), 18, Color("#FF8888"))
	_info_label = _make_label(Vector2(16, 116), 18, Color("#AEE0FF"))

	_end_turn_btn = Button.new()
	_end_turn_btn.text = "结束回合 (Space)"
	_end_turn_btn.position = Vector2(16, 160)
	_end_turn_btn.pressed.connect(_on_end_turn_pressed)
	_hud.add_child(_end_turn_btn)

	_burst_btn = Button.new()
	_burst_btn.text = "羁绊爆发 (B)"
	_burst_btn.position = Vector2(220, 160)
	_burst_btn.disabled = true
	_burst_btn.pressed.connect(_on_burst_pressed)
	_hud.add_child(_burst_btn)

	_refresh_hud()

func _make_label(pos: Vector2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(l)
	return l

func _refresh_hud() -> void:
	_round_label.text = "回合 %d / %d   |   敌方剩余 %d" % [_turn.round_count, SliceConfig.ROUND_LIMIT, _count_alive("enemy")]
	_gauge_label.text = "羁绊槽 %d / %d %s" % [_bond.bond_gauge, SliceConfig.BOND_GAUGE_MAX, "★满！可爆发" if _bond.is_full() else ""]
	_burst_btn.disabled = not _bond.is_full() or _input_locked
	_end_turn_btn.disabled = _input_locked
	match _mode:
		Mode.NORMAL:
			if _selected_id == -1:
				_info_label.text = "点击己方船员选中 → 点空格移动 / 点敌人攻击。凑相邻可 +1 伤害且多充能。"
			else:
				var u: UnitInstance = _units[_selected_id]
				_info_label.text = "已选 %s（已移动:%s 已行动:%s）。点亮格移动；范围内敌人攻击。" % [
					u.definition.display_name, _yn(u.has_moved), _yn(u.has_acted)]
		Mode.BURST_SELECT:
			if _burst_lead_id == -1:
				_info_label.text = "【爆发】点击 lead 船员"
			else:
				_info_label.text = "【爆发】点击相邻的 partner 船员（不同单位）"

func _yn(b: bool) -> String:
	return "是" if b else "否"

# ─────────────────────────── 单位生成 ───────────────────────────

func _spawn_units() -> void:
	# 船员（近端 row 7）
	_add_unit(_def("crew_sword_1", "阿赞", "crew", "swordsman", 10, 3, 1, 3), Vector2i(2, 7))
	_add_unit(_def("crew_sword_2", "梅丽", "crew", "swordsman", 10, 3, 1, 3), Vector2i(3, 7))
	_add_unit(_def("crew_gunner", "炮吉", "crew", "gunner", 8, 2, 3, 3), Vector2i(4, 7))
	_add_unit(_def("crew_bulwark", "铁牛", "crew", "bulwark", 14, 2, 1, 2), Vector2i(5, 7))
	# 敌人（远端 row 1-2，MELEE）
	_add_unit(_def("enemy_1", "海兵甲", "enemy", "swordsman", 6, 2, 1, 2), Vector2i(3, 1))
	_add_unit(_def("enemy_2", "海兵乙", "enemy", "swordsman", 6, 2, 1, 2), Vector2i(4, 1))
	_add_unit(_def("enemy_3", "海兵丙", "enemy", "bulwark", 6, 2, 1, 2), Vector2i(5, 2))
	_recompute_intents()

func _def(id: String, disp_name: String, faction: String, ucls: String, hp: int, mv: int, atk: int, dmg: int) -> UnitDefinition:
	var d := UnitDefinition.new()
	d.id = id
	d.display_name = disp_name
	d.faction = faction
	d.unit_class = ucls
	d.max_hp = hp
	d.move_range = mv
	d.attack_range = atk
	d.base_damage = dmg
	return d

func _add_unit(def: UnitDefinition, pos: Vector2i) -> void:
	var inst := UnitInstance.new(_next_id, def, pos)
	_units[_next_id] = inst
	_board.place(_next_id, pos)
	_unit_layer.spawn_view(def, _next_id, pos)
	_next_id += 1

# ─────────────────────────── 事件 ───────────────────────────

func _connect_events() -> void:
	EventBus.gauge_charged.connect(_on_gauge_charged)
	EventBus.bond_gauge_full.connect(_refresh_hud)
	EventBus.burst_presentation_started.connect(_on_burst_started)
	EventBus.burst_presentation_ended.connect(_on_burst_ended)
	EventBus.battle_won.connect(_on_battle_won)

func _on_gauge_charged(_a: int, _c: int, _t: int) -> void:
	_refresh_hud()

func _on_burst_started() -> void:
	_input_locked = true
	_refresh_hud()

func _on_burst_ended() -> void:
	_input_locked = false
	_clear_highlights()
	_check_win()
	_refresh_hud()

func _on_battle_won() -> void:
	_info_label.text = "★ 胜利！全部敌人被击倒。（核心循环完整跑通）"
	_clear_highlights()

# ─────────────────────────── 输入 ───────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _input_locked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_on_end_turn_pressed()
		elif event.keycode == KEY_B and _bond.is_full():
			_on_burst_pressed()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var gp = _mouse_to_grid()
		if gp == null:
			return
		_handle_click(gp)

func _mouse_to_grid():
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	if abs(dir.y) < 1e-6:
		return null
	var t := -from.y / dir.y
	if t < 0.0:
		return null
	var hit := from + dir * t
	var gp: Vector2i = GridCoordMapper.world_to_grid(hit)
	if not GridCoordMapper.in_bounds(gp):
		return null
	return gp

func _handle_click(gp: Vector2i) -> void:
	if _turn.is_terminal():
		return
	if _mode == Mode.BURST_SELECT:
		_handle_burst_click(gp)
		return
	var clicked_id: int = _board.get_unit_at(gp)
	# 选中己方船员
	if clicked_id != -1 and _units[clicked_id].faction() == "crew":
		_select_unit(clicked_id)
		return
	if _selected_id == -1:
		return
	var sel: UnitInstance = _units[_selected_id]
	# 攻击：点到攻击范围内的敌人
	if clicked_id != -1 and _units[clicked_id].faction() == "enemy":
		if not sel.has_acted and _in_attack_range(sel, _units[clicked_id]):
			_perform_attack(sel, _units[clicked_id])
		return
	# 移动：点到可达空格
	if clicked_id == -1 and not sel.has_moved:
		var reach := _board.reachable_cells(sel.grid_position, sel.definition.move_range)
		if gp in reach:
			_perform_move(sel, gp)

func _select_unit(id: int) -> void:
	if _selected_id != -1:
		var pv: UnitView = _unit_layer.get_view(_selected_id)
		if pv: pv.set_selected(false)
	_selected_id = id
	var v: UnitView = _unit_layer.get_view(id)
	if v: v.set_selected(true)
	_show_selection_highlights(_units[id])
	_refresh_hud()

# ─────────────────────────── 移动 / 攻击 ───────────────────────────

func _perform_move(inst: UnitInstance, to: Vector2i) -> void:
	var from := inst.grid_position
	_board.move(inst.instance_id, from, to)
	inst.grid_position = to
	inst.has_moved = true
	EventBus.unit_moved.emit(inst.instance_id, from, to)
	_show_selection_highlights(inst)
	_refresh_hud()

func _perform_attack(attacker: UnitInstance, target: UnitInstance) -> void:
	var adjacent_ally := _has_adjacent_ally(attacker)
	var dmg := attacker.definition.base_damage + (SliceConfig.ADJACENCY_DAMAGE_BONUS if adjacent_ally else 0)
	target.current_hp -= dmg
	attacker.has_acted = true
	EventBus.attack_executed.emit(attacker.instance_id, target.instance_id, dmg)
	EventBus.damage_dealt.emit(target.instance_id, dmg, max(target.current_hp, 0))
	# 充能（己方攻击才充羁绊槽）
	if attacker.faction() == "crew":
		_bond.on_attack(attacker.instance_id, adjacent_ally)
	if target.current_hp <= 0:
		_down_unit(target)
	_clear_highlights()
	_show_selection_highlights(attacker)
	_refresh_hud()
	_check_win()

func _down_unit(inst: UnitInstance) -> void:
	inst.is_alive = false
	_board.remove_at(inst.grid_position)
	EventBus.unit_downed.emit(inst.instance_id)

func _has_adjacent_ally(inst: UnitInstance) -> bool:
	for id in _units:
		var u: UnitInstance = _units[id]
		if u.instance_id == inst.instance_id or not u.is_alive:
			continue
		if u.faction() == inst.faction() and GridBoard.is_adjacent(u.grid_position, inst.grid_position):
			return true
	return false

func _in_attack_range(attacker: UnitInstance, target: UnitInstance) -> bool:
	var ar := attacker.definition.attack_range
	if ar <= 1:
		return GridBoard.chebyshev(attacker.grid_position, target.grid_position) == 1
	# 远程：曼哈顿，且 ≥ 最小射程
	var md := GridBoard.manhattan(attacker.grid_position, target.grid_position)
	return md >= SliceConfig.GUNNER_MIN_RANGE and md <= ar

# ─────────────────────────── 爆发流程 ───────────────────────────

func _on_burst_pressed() -> void:
	if not _bond.is_full() or _input_locked:
		return
	_mode = Mode.BURST_SELECT
	_burst_lead_id = -1
	_clear_highlights()
	_refresh_hud()

func _handle_burst_click(gp: Vector2i) -> void:
	var id := _board.get_unit_at(gp)
	if id == -1 or _units[id].faction() != "crew":
		return
	if _burst_lead_id == -1:
		_burst_lead_id = id
		_refresh_hud()
		return
	if id == _burst_lead_id:
		return
	var lead: UnitInstance = _units[_burst_lead_id]
	var partner: UnitInstance = _units[id]
	if not GridBoard.is_adjacent(lead.grid_position, partner.grid_position):
		_info_label.text = "【爆发】partner 必须与 lead 相邻——重选"
		return
	_trigger_burst(lead, partner)

func _trigger_burst(lead: UnitInstance, partner: UnitInstance) -> void:
	var effect_id := BondSystem.burst_effect_for(lead.unit_class(), partner.unit_class())
	var dmg := BondSystem.burst_damage(effect_id)
	# 清屏级：命中 lead 周围切比雪夫半径内全部敌人
	for id in _units.keys():
		var u: UnitInstance = _units[id]
		if u.is_alive and u.faction() == "enemy" \
			and GridBoard.chebyshev(u.grid_position, lead.grid_position) <= SliceConfig.BURST_RADIUS:
			u.current_hp -= dmg
			EventBus.damage_dealt.emit(u.instance_id, dmg, max(u.current_hp, 0))
			if u.current_hp <= 0:
				_down_unit(u)
	_bond.reset()
	_mode = Mode.NORMAL
	_burst_lead_id = -1
	EventBus.burst_executed.emit(lead.instance_id, partner.instance_id)
	# 演出（input lock 由 burst_presentation_started 触发）
	EventBus.burst_presentation_requested.emit(lead.instance_id, partner.instance_id, effect_id)
	_refresh_hud()

# ─────────────────────────── 回合推进 ───────────────────────────

func _on_end_turn_pressed() -> void:
	if _input_locked or _turn.is_terminal():
		return
	if _turn.get_state() != TurnManager.BattleState.PLAYER_PHASE:
		return
	_clear_selection()
	_turn.set_state(TurnManager.BattleState.ENEMY_PHASE)
	await _run_enemy_phase()
	if _turn.is_terminal():
		return
	# 回到玩家回合
	for id in _units:
		_units[id].reset_turn_flags()
	_turn.set_state(TurnManager.BattleState.PLAYER_PHASE)
	_recompute_intents()
	_refresh_hud()

func _run_enemy_phase() -> void:
	_info_label.text = "敌方行动中…"
	for id in _units.keys():
		var e: UnitInstance = _units[id]
		if not e.is_alive or e.faction() != "enemy":
			continue
		var target := EnemyAI.nearest_crew(e, _units)
		if target == null:
			continue
		# 不在攻击范围则逼近一步
		if not _in_attack_range(e, target):
			var dest := EnemyAI.step_toward(e, target.grid_position, _board)
			if dest != e.grid_position:
				_perform_move(e, dest)
				await get_tree().create_timer(0.25).timeout
		# 在范围则攻击
		if _in_attack_range(e, target):
			_perform_attack(e, target)
			await get_tree().create_timer(0.2).timeout
		if _check_loss():
			return

func _recompute_intents() -> void:
	var lines: Array[String] = []
	for id in _units.keys():
		var e: UnitInstance = _units[id]
		if not e.is_alive or e.faction() != "enemy":
			continue
		var intent := EnemyAI.intent_for(e, _units)
		if intent["target_id"] == -1:
			continue
		var tname: String = _units[intent["target_id"]].definition.display_name
		lines.append("%s → %s%s" % [e.definition.display_name, tname, "（攻击）" if intent["will_attack"] else "（逼近）"])
	_intent_label.text = "敌人意图： " + ("  ".join(lines) if not lines.is_empty() else "—")

# ─────────────────────────── 胜负 ───────────────────────────

func _check_win() -> void:
	if _count_alive("enemy") == 0 and not _turn.is_terminal():
		_turn.set_state(TurnManager.BattleState.BATTLE_WIN)

func _check_loss() -> bool:
	if _count_alive("crew") == 0 and not _turn.is_terminal():
		_turn.set_state(TurnManager.BattleState.BATTLE_LOSS)
		_info_label.text = "战败：全部船员阵亡。"
		return true
	return false

func _count_alive(faction: String) -> int:
	var n := 0
	for id in _units:
		var u: UnitInstance = _units[id]
		if u.is_alive and u.faction() == faction:
			n += 1
	return n

# ─────────────────────────── 高亮 ───────────────────────────

func _show_selection_highlights(inst: UnitInstance) -> void:
	_clear_highlights()
	if inst.faction() != "crew" or _mode != Mode.NORMAL:
		return
	if not inst.has_moved:
		for c in _board.reachable_cells(inst.grid_position, inst.definition.move_range):
			_add_highlight(c, Color("#00CCCC"))   # 移动青（art-bible §4.3）
	if not inst.has_acted:
		for id in _units.keys():
			var u: UnitInstance = _units[id]
			if u.is_alive and u.faction() == "enemy" and _in_attack_range(inst, u):
				_add_highlight(u.grid_position, Color("#FF2222"))  # 攻击红

func _add_highlight(gp: Vector2i, color: Color) -> void:
	var hl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SliceConfig.CELL_SIZE * 0.9, SliceConfig.CELL_SIZE * 0.9)
	hl.mesh = pm
	hl.position = GridCoordMapper.grid_to_world(gp)
	hl.position.y = 0.02   # 略高于格面防 z-fighting（ADR-0006）
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hl.material_override = mat
	_highlight_root.add_child(hl)
	_highlights.append(hl)

func _clear_highlights() -> void:
	for h in _highlights:
		if is_instance_valid(h):
			h.queue_free()
	_highlights.clear()

func _clear_selection() -> void:
	if _selected_id != -1:
		var v: UnitView = _unit_layer.get_view(_selected_id)
		if v: v.set_selected(false)
	_selected_id = -1
	_clear_highlights()
