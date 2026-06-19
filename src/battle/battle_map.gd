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

var _map_state: MapState = MapState.MAP_UNLOADED

func get_map_state() -> MapState:
	return _map_state

func is_map_ready() -> bool:
	return _map_state == MapState.MAP_READY

func get_deploy_zone_available(_occupied: Array = []) -> Array[Vector2i]:
	return []  # TODO(battle-map deploy story)：返回 _valid_deploy_cells 减 _occupied。

# 由 BattleScene._ready() 调用（ADR-0002 / architecture.md 4d）。
func load_map(_island_index: int) -> void:
	# TODO(battle-map deploy story)：MapDataManager.get_map → validate_map →
	#   写地形 + 生成敌方 UnitInstance + place_unit（需 UnitInstance 类）→
	#   注册 _valid_deploy_cells → EventBus.map_loaded / map_load_failed；推进 MAP_* 状态机。
	pass

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
