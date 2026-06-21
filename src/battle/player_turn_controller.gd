# 玩家回合输入控制器（Node）。阶段制：我方回合内玩家**自由点选**任意己方单位指挥
# （移动/攻击/职业动词，三行动点任意顺序），全部满意后"结束我方回合" → 敌方回合。
# 本控制器不产生战斗逻辑：把输入翻译成对 GridBoard/BattleResolution/BondGaugeBurst/TurnManager 的调用。
# 逻辑（选择+目标计算+派发）可单测；鼠标拾取/高亮/HUD 为视觉层（F5 验证）。
class_name PlayerTurnController
extends Node

enum Mode { IDLE, MOVE, ATTACK, BURST_LEAD, BURST_PARTNER, VERB }

var _turn_manager: TurnManager
var _grid_board: GridBoard
var _battle_resolution: BattleResolution
var _bond_gauge_burst: BondGaugeBurst
var _highlighter: Node = null   # BoardHighlighter（可空，测试不注入）
var _hud: Node = null           # BattleHUD（可空）

var _phase_active: bool = false   # 我方回合中（允许输入）
var _selected_unit_id: int = -1   # 当前被指挥的己方单位（-1 = 未选）
var _mode: int = Mode.IDLE
var _valid_targets: Array[Vector2i] = []
var _burst_lead_id: int = -1
var _pending_verb: int = -1   # VERB 选靶模式下待派发的 BattleResolution.VerbType

func setup(turn_manager: TurnManager, grid_board: GridBoard, battle_resolution: BattleResolution, bond_gauge_burst: BondGaugeBurst, highlighter: Node = null, hud: Node = null) -> void:
	_turn_manager = turn_manager
	_grid_board = grid_board
	_battle_resolution = battle_resolution
	_bond_gauge_burst = bond_gauge_burst
	_highlighter = highlighter
	_hud = hud
	if not EventBus.player_phase_started.is_connected(_on_player_phase_started):
		EventBus.player_phase_started.connect(_on_player_phase_started)
	if not EventBus.enemy_phase_started.is_connected(_on_enemy_phase_started):
		EventBus.enemy_phase_started.connect(_on_enemy_phase_started)
	if not EventBus.battle_won.is_connected(_on_battle_over):
		EventBus.battle_won.connect(_on_battle_over)
	if not EventBus.battle_lost.is_connected(_on_battle_over):
		EventBus.battle_lost.connect(_on_battle_over)

func _on_player_phase_started() -> void:
	_phase_active = true
	_selected_unit_id = -1
	_burst_lead_id = -1
	_set_mode(Mode.IDLE)

func _on_enemy_phase_started() -> void:
	_phase_active = false
	_selected_unit_id = -1
	_set_mode(Mode.IDLE)

func _on_battle_over() -> void:
	_phase_active = false
	_selected_unit_id = -1
	_set_mode(Mode.IDLE)

# HUD 不会自动感知控制器状态变化（选中/模式/行动点不发信号）→ 每次状态变化主动刷新。
func _refresh_hud() -> void:
	if _hud != null and _hud.has_method("refresh"):
		_hud.refresh()

# 内部：清模式 + 清高亮（不计算目标，不改选中单位）。
func _set_mode(mode: int) -> void:
	_mode = mode
	_valid_targets = []
	if _highlighter != null:
		_highlighter.clear()
	_refresh_hud()

# 公开：进入模式 → 计算合法目标 → 高亮。
func set_mode(mode: int) -> void:
	if not _phase_active:
		return
	_mode = mode
	_valid_targets = _compute_targets(mode)
	if _highlighter != null:
		if _valid_targets.is_empty():
			_highlighter.clear()
		else:
			_highlighter.show_cells(_valid_targets, _color_for(mode))
	_refresh_hud()

func cancel() -> void:
	_set_mode(Mode.IDLE)

# 选中一个己方单位指挥（点击空闲态下的己方单位格触发）。
func select_unit(unit_id: int) -> void:
	var u: UnitInstance = _turn_manager.get_unit(unit_id)
	if u == null or not u.is_alive or u.definition.faction != "crew":
		return
	_selected_unit_id = unit_id
	_set_mode(Mode.IDLE)

func handle_cell_click(cell: Vector2i) -> void:
	if not _phase_active:
		return
	# 空闲态点己方单位 = 选中指挥对象。
	if _mode == Mode.IDLE:
		var ally := _ally_at(cell)
		if ally != -1:
			select_unit(ally)
		return
	if not cell in _valid_targets:
		return
	match _mode:
		Mode.MOVE:
			_do_move(cell)
		Mode.ATTACK:
			_do_attack(cell)
		Mode.BURST_LEAD:
			_select_burst_lead(cell)
		Mode.BURST_PARTNER:
			_do_burst(cell)
		Mode.VERB:
			_do_verb_on_cell(cell)

func _compute_targets(mode: int) -> Array[Vector2i]:
	match mode:
		Mode.MOVE:
			var u: UnitInstance = _turn_manager.get_unit(_selected_unit_id)
			if u == null or u.has_moved:
				return []
			return _grid_board.get_reachable_cells(u.grid_position, u.definition.move_range)
		Mode.ATTACK:
			var u: UnitInstance = _turn_manager.get_unit(_selected_unit_id)
			if u == null or u.has_acted:
				return []
			var cells: Array[Vector2i] = []
			for eid in _turn_manager.get_alive_enemies():
				if _battle_resolution.is_valid_attack(_selected_unit_id, eid):
					cells.append(_turn_manager.get_unit(eid).grid_position)
			return cells
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
		Mode.VERB:
			var u: UnitInstance = _turn_manager.get_unit(_selected_unit_id)
			if u == null or u.has_used_verb:
				return []
			var cells: Array[Vector2i] = []
			match u.definition.class_action_id:
				"heal":
					for aid in _turn_manager.get_alive_allies():
						if aid == _selected_unit_id:
							continue
						var a: UnitInstance = _turn_manager.get_unit(aid)
						if GridBoard.chebyshev(u.grid_position, a.grid_position) == 1:
							cells.append(a.grid_position)
				"displace":
					for eid in _turn_manager.get_alive_enemies():
						var e: UnitInstance = _turn_manager.get_unit(eid)
						if GridBoard.chebyshev(u.grid_position, e.grid_position) == 1:
							cells.append(e.grid_position)
			return cells
		_:
			return []

func _do_move(cell: Vector2i) -> void:
	_grid_board.forced_move_unit(_selected_unit_id, cell)
	_turn_manager.get_unit(_selected_unit_id).grid_position = cell
	_turn_manager.mark_has_moved(_selected_unit_id)
	_set_mode(Mode.IDLE)

func _enemy_at(cell: Vector2i) -> int:
	for eid in _turn_manager.get_alive_enemies():
		if _turn_manager.get_unit(eid).grid_position == cell:
			return eid
	return -1

func _do_attack(cell: Vector2i) -> void:
	var target := _enemy_at(cell)
	if target == -1:
		return
	_battle_resolution.execute_attack(_selected_unit_id, target)
	_set_mode(Mode.IDLE)

# HUD[技能]按钮调用。无目标动词（slash/guard/aura）立即执行；需目标的动词留 MVP 后续 story。
func do_verb() -> void:
	if not _phase_active or _selected_unit_id == -1:
		return
	var u: UnitInstance = _turn_manager.get_unit(_selected_unit_id)
	if u == null or u.has_used_verb or u.definition.class_action_id == "":
		return
	match u.definition.class_action_id:
		"slash":
			_battle_resolution.execute_slash(_selected_unit_id)
		"guard":
			_battle_resolution.execute_guard(_selected_unit_id, _selected_unit_id)
		"aura":
			_battle_resolution.execute_aura(_selected_unit_id)
		"heal", "displace":
			_begin_verb_targeting()   # 需选目标 → 进 VERB 选靶模式（不在此清模式）
			return
		_:
			push_warning("PlayerTurnController.do_verb: MVP 未支持动词 %s（cannon 定向选靶留后续 story）" % u.definition.class_action_id)
			return
	_set_mode(Mode.IDLE)

# 进入动词选靶：记待派发 VerbType，算相邻合法目标并高亮。
func _begin_verb_targeting() -> void:
	_pending_verb = _verb_type_for(_turn_manager.get_unit(_selected_unit_id).definition.class_action_id)
	set_mode(Mode.VERB)

func _verb_type_for(class_action_id: String) -> int:
	match class_action_id:
		"heal":
			return BattleResolution.VerbType.HEAL
		"displace":
			return BattleResolution.VerbType.MOVE   # MOVE 分发到 execute_displace（方向引擎内推导）
		_:
			return -1

# VERB 模式点击合法目标格 → 经统一分发器执行（方向型动词内部推导方向）。
func _do_verb_on_cell(cell: Vector2i) -> void:
	var cid := _turn_manager.get_unit(_selected_unit_id).definition.class_action_id
	var target := _ally_at(cell) if cid == "heal" else _enemy_at(cell)
	if target == -1:
		return
	_battle_resolution.execute_verb(_selected_unit_id, _pending_verb, target)
	_set_mode(Mode.IDLE)

# HUD[爆发]按钮调用（仅槽满时按钮可点）。
func begin_burst_targeting() -> void:
	if not _phase_active or not _bond_gauge_burst.is_full():
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

# 玩家点"结束我方回合"调用。
func end_player_phase() -> void:
	if not _phase_active:
		return
	_phase_active = false
	_selected_unit_id = -1
	_set_mode(Mode.IDLE)
	_turn_manager.end_player_phase()

func get_available_actions() -> Dictionary:
	var result := {"move": false, "attack": false, "verb": false, "burst": false}
	if not _phase_active:
		return result
	result["burst"] = _bond_gauge_burst.is_full()
	var u: UnitInstance = _turn_manager.get_unit(_selected_unit_id)
	if u == null:
		return result
	result["move"] = not u.has_moved and not _grid_board.get_reachable_cells(u.grid_position, u.definition.move_range).is_empty()
	if not u.has_acted:
		for eid in _turn_manager.get_alive_enemies():
			if _battle_resolution.is_valid_attack(_selected_unit_id, eid):
				result["attack"] = true
				break
	if not u.has_used_verb:
		var cid := u.definition.class_action_id
		if cid in ["slash", "guard", "aura"]:
			result["verb"] = true          # 无目标动词恒可用
		elif cid in ["heal", "displace"]:
			result["verb"] = not _compute_targets(Mode.VERB).is_empty()   # 需有相邻合法目标
	return result

func _color_for(mode: int) -> Color:
	match mode:
		Mode.MOVE: return Color("#22FF66")
		Mode.ATTACK: return Color("#FF2222")
		_: return Color("#FFCC00")

# ── 查询接口（供测试 + HUD）──
func is_phase_active() -> bool:
	return _phase_active

# 是否有选中单位可指挥（HUD 据此启用移动/攻击/技能按钮 + 显示单位信息）。
func is_active() -> bool:
	return _phase_active and _selected_unit_id != -1

func get_mode() -> int:
	return _mode

func get_current_unit_id() -> int:
	return _selected_unit_id

func get_valid_targets() -> Array[Vector2i]:
	return _valid_targets

# ── 视觉壳（F5；鼠标拾取 → 格 → handle_cell_click；Esc 取消模式）──
func _unhandled_input(event: InputEvent) -> void:
	if not _phase_active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _resolve_click_cell(event.position)
		if cell != Vector2i(-1, -1):
			handle_cell_click(cell)

const _UNIT_PICK_RADIUS_PX: float = 70.0   # 屏幕空间单位拾取半径

# 解析点击落到哪个逻辑格：选单位/选目标时优先按屏幕空间最近单位拾取（单位是高方块，
# 仅靠地面射线会落到身后格）；移动模式点空格仍用地面射线。
func _resolve_click_cell(screen_pos: Vector2) -> Vector2i:
	if _mode != Mode.MOVE:
		var uid := _pick_unit_at_screen(screen_pos)
		if uid != -1:
			return _turn_manager.get_unit(uid).grid_position
	return _screen_to_cell(screen_pos)

# 投影所有存活单位中心到屏幕，返回离点击最近且在半径内者的 battle_id（无则 -1）。
func _pick_unit_at_screen(screen_pos: Vector2) -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return -1
	var best := -1
	var best_d := _UNIT_PICK_RADIUS_PX
	for id in _turn_manager.get_alive_allies() + _turn_manager.get_alive_enemies():
		var u: UnitInstance = _turn_manager.get_unit(id)
		var world := GridCoordMapper.grid_to_world(u.grid_position) + Vector3(0, 0.75, 0)
		if cam.is_position_behind(world):
			continue
		var d := cam.unproject_position(world).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = id
	return best

# 鼠标屏幕坐标 → 与 y=0 棋盘平面求交 → 逻辑格（非物理拾取，ADR-0007）。
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
