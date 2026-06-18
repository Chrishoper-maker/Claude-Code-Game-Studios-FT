# 棋盘空间逻辑（8×8，纯 GDScript，architecture.md §134 / grid-board-system）。
# 骨架 stub：接口签名就位，实现留 grid-board story。
class_name GridBoard
extends Node

func get_cell(_pos: Vector2i) -> int: return -1                       # 占位：返回 unit_id 或 -1
func get_adjacents(_pos: Vector2i) -> Array[Vector2i]: return []
func get_reachable_cells(_id: int, _move_range: int) -> Array[Vector2i]: return []
func in_attack_range(_a: int, _b: int, _attack_range: int) -> bool: return false
func place_unit(_id: int, _pos: Vector2i) -> void: pass
func remove_unit(_id: int) -> void: pass
func forced_move_unit(_id: int, _dest: Vector2i) -> void: pass
func grid_to_world(_pos: Vector2i) -> Vector3: return Vector3.ZERO    # 实现委托 ADR-0006 GridCoordMapper
func world_to_grid(_world: Vector3) -> Vector2i: return Vector2i.ZERO
