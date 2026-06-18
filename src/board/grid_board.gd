# 棋盘空间逻辑（8×8，纯 GDScript，grid-board-system / architecture.md §134）。
# 一切空间逻辑的事实源：占用状态 + 空间查询 + 位置合法性。"相邻"几何的唯一权威。
# 世界坐标映射属实现层，委托 ADR-0006 GridCoordMapper（GDD §10）。
class_name GridBoard
extends Node

const BOARD_SIZE := 8
const EMPTY := -1

const _DIRS_4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const _DIRS_8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _occupancy: Dictionary = {}    # Vector2i → int unit_id
var _unit_pos: Dictionary = {}     # int unit_id → Vector2i（反向，O(1) remove/move）
var _blocked: Dictionary = {}      # Vector2i → true（TERRAIN_BLOCKED）

# ── 公式 1：越界 ──
func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_SIZE and pos.y >= 0 and pos.y < BOARD_SIZE

# ── 公式 2：切比雪夫 / 相邻（八向，本系统唯一权威）──
static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

static func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return chebyshev(a, b) == 1

# ── 占用 ──
func get_cell(pos: Vector2i) -> int:
	return _occupancy.get(pos, EMPTY)

# 可进入 = 在界内 且 无占用 且 无地形阻挡
func is_empty(pos: Vector2i) -> bool:
	return in_bounds(pos) and not _occupancy.has(pos) and not _blocked.has(pos)

func place_unit(id: int, pos: Vector2i) -> void:
	_occupancy[pos] = id
	_unit_pos[id] = pos

func remove_unit(id: int) -> void:
	if _unit_pos.has(id):
		_occupancy.erase(_unit_pos[id])
		_unit_pos.erase(id)

func forced_move_unit(id: int, dest: Vector2i) -> void:
	if _unit_pos.has(id):
		_occupancy.erase(_unit_pos[id])
	_occupancy[dest] = id
	_unit_pos[id] = dest

func get_unit_pos(id: int) -> Vector2i:
	return _unit_pos.get(id, Vector2i(EMPTY, EMPTY))

func set_blocked(pos: Vector2i, blocked: bool) -> void:
	if blocked:
		_blocked[pos] = true
	else:
		_blocked.erase(pos)

# ── 相邻占用查询（八向，返回 unit_id 列表）──
func get_adjacents(pos: Vector2i) -> Array[int]:
	var ids: Array[int] = []
	for d in _DIRS_8:
		var n: Vector2i = pos + d
		if _occupancy.has(n):
			ids.append(_occupancy[n])
	return ids

# ── 公式 3：攻击范围（双度量；range==1 近战切比雪夫，否则远程曼哈顿）──
func in_attack_range(a: Vector2i, b: Vector2i, attack_range: int) -> bool:
	if attack_range == 1:
		return chebyshev(a, b) <= 1
	return manhattan(a, b) <= attack_range

# ── 4向BFS 可达（move_range 步数上限；障碍/占用/越界不可穿越；不含起点）──
func get_reachable_cells(pos: Vector2i, move_range: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var visited: Dictionary = {pos: 0}
	var queue: Array[Vector2i] = [pos]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		var dist: int = visited[cur]
		if dist >= move_range:
			continue
		for d in _DIRS_4:
			var nxt: Vector2i = cur + d
			if visited.has(nxt) or not is_empty(nxt):
				continue
			visited[nxt] = dist + 1
			result.append(nxt)
			queue.append(nxt)
	return result

# 世界坐标映射委托 ADR-0006 GridCoordMapper（GDD §10：映射属实现层）。
func grid_to_world(_pos: Vector2i) -> Vector3: return Vector3.ZERO     # TODO(ADR-0006)
func world_to_grid(_world: Vector3) -> Vector2i: return Vector2i.ZERO  # TODO(ADR-0006)
