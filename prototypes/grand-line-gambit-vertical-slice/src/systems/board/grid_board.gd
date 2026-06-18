# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: 棋盘空间逻辑（占用唯一事实源 + BFS 可达 + 双度量距离，grid-board GDD）
# Date: 2026-06-18
#
# 逻辑棋盘（纯数据，无 3D 节点）。唯一占用事实源：get_unit_at(pos) -> instance_id 或 -1。
class_name GridBoard
extends RefCounted

const SIZE: int = SliceConfig.BOARD_SIZE

var _occupancy: Dictionary = {}      # Vector2i -> int instance_id

func clear() -> void:
	_occupancy.clear()

func place(instance_id: int, pos: Vector2i) -> void:
	_occupancy[pos] = instance_id

func remove_at(pos: Vector2i) -> void:
	_occupancy.erase(pos)

func move(instance_id: int, from_pos: Vector2i, to_pos: Vector2i) -> void:
	_occupancy.erase(from_pos)
	_occupancy[to_pos] = instance_id

func get_unit_at(pos: Vector2i) -> int:
	return _occupancy.get(pos, -1)

func is_empty(pos: Vector2i) -> bool:
	return GridCoordMapper.in_bounds(pos) and not _occupancy.has(pos)

# 切比雪夫距离（相邻定义 / 近战攻击）
static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))

# 曼哈顿距离（远程攻击）
static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

# 八向相邻（切比雪夫=1）
static func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return a != b and chebyshev(a, b) == 1

# BFS 4 向可达格（含阻挡排除；起点不返回）
func reachable_cells(start: Vector2i, move_range: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var visited := {start: 0}
	var queue: Array[Vector2i] = [start]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		var dist: int = visited[cur]
		if dist >= move_range:
			continue
		for d in dirs:
			var nxt: Vector2i = cur + d
			if visited.has(nxt):
				continue
			if not is_empty(nxt):
				continue
			visited[nxt] = dist + 1
			result.append(nxt)
			queue.append(nxt)
	return result
