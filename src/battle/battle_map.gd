# 地图加载/校验（architecture.md §136 / battle-map-system）。MAP_* 状态机（ADR-0004）。
# 验证内核（Rule 3 验证序列 ①–⑨ / 公式 F1–F6）已实现；
# 部署阶段（地形写入 + UnitInstance 生成 + place）需 UnitInstance 类，留 TODO。
class_name BattleMap
extends Node

enum MapState {
	MAP_UNLOADED,
	MAP_VALIDATING,
	MAP_LOADING,
	MAP_READY,
	MAP_ACTIVE,
	MAP_RESOLVED,
}

# 旋钮常量（battle-map-system §Tuning Knobs / entities.yaml）。
const TERRAIN_BLOCKED_MAX := 16        # F1：n_blocked ≤ 16（= 0.25 × 64）
const DEPLOY_ZONE_MIN_CELLS := 6       # F2
const ENEMY_COUNT_MIN := 2             # F3
const ENEMY_COUNT_MAX := 6             # F3
const MAP_SEPARATION_MIN := 3          # F4
const RANGED_CORRIDOR_MIN_LENGTH := 3  # F6
const BOARD_SIZE := 8

const MVP_MAP_ID := "battle_map_001"           # MVP：固定单图（航线系统接管前）

var _map_state: MapState = MapState.MAP_UNLOADED
var _valid_deploy_cells: Array[Vector2i] = []  # 加载时扣除 BLOCKED 重叠后的有效部署格
var _blocked_cells: Array[Vector2i] = []       # 本图写入棋盘的 BLOCKED 格（reset 时清）
var _deployed_ids: Array[int] = []             # 已 place 的敌方 battle_id（reset 时移除）
var _deployed_crew_ids: Array[int] = []        # 已 place 的玩家方 battle_id（reset 时移除）
var _grid_board: GridBoard = null              # 加载时注入引用（reset 复用）
var _turn_manager: TurnManager = null          # 场景胶水注入（load_map 用）

# BattleScene._ready 注入兄弟节点引用（场景胶水）。
func setup(grid_board: GridBoard, turn_manager: TurnManager) -> void:
	_grid_board = grid_board
	_turn_manager = turn_manager

func get_map_state() -> MapState:
	return _map_state

func is_map_ready() -> bool:
	return _map_state == MapState.MAP_READY

# 返回有效部署格减去 occupied（Rule 4，本系统唯一所有者）。
func get_deploy_zone_available(occupied: Array = []) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _valid_deploy_cells:
		if not c in occupied:
			out.append(c)
	return out

# 玩家方部署（route-recruitment confirm_deploy 后端 / DeployScreen 提交点）：
# 将选定 crew 放入部署区指定格。验证：MAP_READY + 数量匹配 + 每格在部署区/不重复/未占用。
# 全部合法才落地（任一非法返回 false，不部署任何单位）。crew battle_id 入 _deployed_crew_ids（reset 清）。
func deploy_crew(crew_defs: Array, positions: Array, equipments: Array = []) -> bool:
	if _map_state != MapState.MAP_READY:
		return false
	if crew_defs.is_empty() or crew_defs.size() != positions.size():
		return false
	var seen: Dictionary = {}
	for pos in positions:
		if not pos in _valid_deploy_cells:
			return false
		if seen.has(pos):
			return false
		seen[pos] = true
		if not _grid_board.is_empty(pos):
			return false
	for i in crew_defs.size():
		var eq: EquipmentDefinition = null
		if i < equipments.size():
			eq = equipments[i]
		var inst := UnitInstance.from_definition(crew_defs[i], eq)
		inst.grid_position = positions[i]
		var battle_id := _turn_manager.register_unit(inst)
		_grid_board.place_unit(battle_id, positions[i])
		_deployed_crew_ids.append(battle_id)
	return true

# 由 BattleScene._ready() 调用（ADR-0002 / architecture.md 4d）。需先 setup() 注入引用。
# 航线系统：加载 RunManager 选定的地图；未选（空）回退 MVP_MAP_ID（测试/异常安全）。
func load_map(_island_index: int) -> void:
	var chosen := RunManager.get_chosen_map_id()
	var map_id := chosen if chosen != "" else MVP_MAP_ID
	var map_def := MapDataManager.get_map(map_id)
	if map_def == null:
		EventBus.map_load_failed.emit(&"map_not_found")
		return
	load_map_definition(map_def, _grid_board, _turn_manager)  # unit_lookup 默认走 UnitDataManager

# 部署核心（Rule 3 步骤 1-5）：验证 → 写地形 → 生成/注册/place 敌人 → 注册部署区 → map_loaded。
# 依赖注入 grid_board / turn_manager / unit_lookup（coding-standards DI）。返回是否成功。
func load_map_definition(map_def: MapDefinition, grid_board: GridBoard, turn_manager: TurnManager, unit_lookup: Callable = Callable()) -> bool:
	# EC-9：MAP_ACTIVE 拒绝新加载（不中断进行中战斗）。
	if _map_state == MapState.MAP_ACTIVE:
		EventBus.map_load_failed.emit(&"map_already_active")
		return false

	# ① 验证（短路）
	_map_state = MapState.MAP_VALIDATING
	var reason := validate_map(map_def, unit_lookup)
	if reason != &"":
		_map_state = MapState.MAP_UNLOADED
		EventBus.map_load_failed.emit(reason)
		return false

	var lookup := unit_lookup if unit_lookup.is_valid() else (func(id: String) -> UnitDefinition: return UnitDataManager.get_unit(id))
	_map_state = MapState.MAP_LOADING
	_grid_board = grid_board
	_turn_manager = turn_manager   # 持久化供 deploy_crew（玩家方部署在加载后调用）

	# ② 写地形（MVP：仅 BLOCKED；COVER 推迟）
	_blocked_cells = []
	for cell in map_def.terrain_data:
		if cell.type == "BLOCKED":
			grid_board.set_blocked(cell.pos, true)
			_blocked_cells.append(cell.pos)

	# ③ 部署敌方：生成 UnitInstance → 写 behavior/home → 注册 battle_id → place
	_deployed_ids = []
	for slot in map_def.enemy_roster:
		var def: UnitDefinition = lookup.call(slot.unit_definition_id)
		var inst := UnitInstance.from_definition(def)
		inst.behavior_type = slot.behavior_type
		inst.home_pos = slot.home_pos
		inst.grid_position = slot.grid_position
		var battle_id := turn_manager.register_unit(inst)
		grid_board.place_unit(battle_id, slot.grid_position)
		_deployed_ids.append(battle_id)

	# ④ 注册部署区（扣除 BLOCKED 重叠）
	_deployed_crew_ids = []
	var blocked_set: Dictionary = {}
	for p in _blocked_cells:
		blocked_set[p] = true
	_valid_deploy_cells = []
	for d in map_def.deploy_zone:
		if not blocked_set.has(d):
			_valid_deploy_cells.append(d)

	# ⑤ 完成
	_map_state = MapState.MAP_READY
	EventBus.map_loaded.emit(map_def.map_id)
	return true

# ── 状态机转换（由 BattleScene 将 EventBus 信号连到这些方法）──
func on_battle_started() -> void:
	if _map_state == MapState.MAP_READY:
		_map_state = MapState.MAP_ACTIVE

func on_battle_won() -> void:
	if _map_state == MapState.MAP_ACTIVE:
		_map_state = MapState.MAP_RESOLVED

func on_battle_lost() -> void:
	if _map_state == MapState.MAP_ACTIVE:
		_map_state = MapState.MAP_RESOLVED

# MAP_RESOLVED → 清空棋盘地形与敌方单位 → MAP_UNLOADED。
func on_map_reset() -> void:
	if _map_state != MapState.MAP_RESOLVED:
		return
	if _grid_board != null:
		for p in _blocked_cells:
			_grid_board.set_blocked(p, false)
		for id in _deployed_ids:
			_grid_board.remove_unit(id)
		for id in _deployed_crew_ids:
			_grid_board.remove_unit(id)
	_valid_deploy_cells = []
	_blocked_cells = []
	_deployed_ids = []
	_deployed_crew_ids = []
	_map_state = MapState.MAP_UNLOADED

# ── 验证内核：Rule 3 验证序列 ①–⑨，短路返回首个失败 reason；&"" 表示全部通过 ──
# unit_lookup(id: String) -> UnitDefinition（注入；默认走 UnitDataManager autoload）。
func validate_map(map_def: MapDefinition, unit_lookup: Callable = Callable()) -> StringName:
	var lookup := unit_lookup if unit_lookup.is_valid() else (func(id: String) -> UnitDefinition: return UnitDataManager.get_unit(id))

	# 收集 BLOCKED 格集合（COVER 不计入阻挡）。
	var blocked: Dictionary = {}
	for cell in map_def.terrain_data:
		if cell.type == "BLOCKED":
			blocked[cell.pos] = true

	# ① F1 地形密度
	if blocked.size() > TERRAIN_BLOCKED_MAX:
		return &"terrain_density_exceeded"

	# ② F3 敌方数量
	var n_enemies := map_def.enemy_roster.size()
	if n_enemies < ENEMY_COUNT_MIN:
		return &"enemy_count_below_minimum"
	if n_enemies > ENEMY_COUNT_MAX:
		return &"enemy_count_above_maximum"

	# ③ 敌方起始格冲突
	var seen: Dictionary = {}
	for slot in map_def.enemy_roster:
		if seen.has(slot.grid_position):
			return &"enemy_position_collision"
		seen[slot.grid_position] = true

	# ④ 敌方起始格落在 BLOCKED
	for slot in map_def.enemy_roster:
		if blocked.has(slot.grid_position):
			return &"enemy_start_blocked"

	# ⑤ F2 部署区有效格数（扣除 BLOCKED 重叠）— 必须先于 ⑥
	var valid_deploy: Array[Vector2i] = []
	for d in map_def.deploy_zone:
		if not blocked.has(d):
			valid_deploy.append(d)
	if valid_deploy.size() < DEPLOY_ZONE_MIN_CELLS:
		return &"deploy_zone_insufficient"

	# ⑥ F4 最小分离距离（依赖 ⑤ 保证 valid_deploy 非空，加防御 guard）
	if valid_deploy.is_empty():
		return &"deploy_zone_insufficient"
	for slot in map_def.enemy_roster:
		for d in valid_deploy:
			if GridBoard.manhattan(slot.grid_position, d) < MAP_SEPARATION_MIN:
				return &"separation_constraint_violated"

	# ⑦ 所有 unit_definition_id 存在
	var allowed := _allowed_threat_tiers(map_def.island_tier)
	for slot in map_def.enemy_roster:
		var def: UnitDefinition = lookup.call(slot.unit_definition_id)
		if def == null:
			return &"unknown_unit_definition"
		# ⑧ F5 威胁层级匹配
		if not (def as EnemyDefinition).threat_tier in allowed:
			return &"threat_tier_mismatch"

	# ⑨ F6 远程走廊
	if not has_valid_ranged_corridor(blocked.keys()):
		return &"no_ranged_corridor"

	return &""

# F5：岛屿等级 → 允许的敌方威胁层级。
func _allowed_threat_tiers(island_tier: int) -> Array:
	match island_tier:
		1, 2: return [1]
		3, 4: return [1, 2]
		5: return [2, 3]
		6: return [3]
	return []

# ── F6 远程走廊检测：存在长度 ≥ RANGED_CORRIDOR_MIN_LENGTH 的连续非 BLOCKED 行/列序列，
#    且序列中至少一格位于边界或邻接 BLOCKED（单侧约束）──
func has_valid_ranged_corridor(blocked_cells: Array) -> bool:
	var blocked: Dictionary = {}
	for c in blocked_cells:
		blocked[c] = true
	# 行扫描（固定 row=y，遍历 col=x）
	for y in BOARD_SIZE:
		var seq: Array[Vector2i] = []
		for x in BOARD_SIZE:
			var cell := Vector2i(x, y)
			if blocked.has(cell):
				if _corridor_ok(seq, "ROW", blocked):
					return true
				seq = []
			else:
				seq.append(cell)
		if _corridor_ok(seq, "ROW", blocked):
			return true
	# 列扫描（固定 col=x，遍历 row=y）
	for x in BOARD_SIZE:
		var seq2: Array[Vector2i] = []
		for y in BOARD_SIZE:
			var cell := Vector2i(x, y)
			if blocked.has(cell):
				if _corridor_ok(seq2, "COL", blocked):
					return true
				seq2 = []
			else:
				seq2.append(cell)
		if _corridor_ok(seq2, "COL", blocked):
			return true
	return false

func _corridor_ok(seq: Array[Vector2i], axis: String, blocked: Dictionary) -> bool:
	return seq.size() >= RANGED_CORRIDOR_MIN_LENGTH and _has_wall_on_side(seq, axis, blocked)

# 单侧约束：序列中至少一格在边界，或其垂直于走廊方向上邻接 BLOCKED。
func _has_wall_on_side(seq: Array[Vector2i], axis: String, blocked: Dictionary) -> bool:
	for c in seq:
		if axis == "ROW":
			if c.y == 0 or c.y == BOARD_SIZE - 1:
				return true
			if blocked.has(Vector2i(c.x, c.y - 1)) or blocked.has(Vector2i(c.x, c.y + 1)):
				return true
		else:  # COL
			if c.x == 0 or c.x == BOARD_SIZE - 1:
				return true
			if blocked.has(Vector2i(c.x - 1, c.y)) or blocked.has(Vector2i(c.x + 1, c.y)):
				return true
	return false
