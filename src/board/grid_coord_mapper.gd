# 全局无状态坐标工具（ADR-0006）。全项目唯一逻辑格↔世界坐标映射；
# 禁止任何系统内联 col*CELL_SIZE —— 一律调用本工具。
class_name GridCoordMapper

const CELL_SIZE: float = 2.0
const BOARD_SIZE: int = 8

# 逻辑格 → 世界坐标：(col,row) → (col*CELL_SIZE, 0, row*CELL_SIZE)。XZ 平面。
static func grid_to_world(grid_pos: Vector2i) -> Vector3:
	return Vector3(grid_pos.x * CELL_SIZE, 0.0, grid_pos.y * CELL_SIZE)

# 世界坐标 → 逻辑格（光标拾取，roundi 取最近格）。
static func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(roundi(world_pos.x / CELL_SIZE), roundi(world_pos.z / CELL_SIZE))

# 棋盘中心世界坐标（相机 look_at 目标）。
static func board_center() -> Vector3:
	var c := (BOARD_SIZE - 1) / 2.0 * CELL_SIZE
	return Vector3(c, 0.0, c)

static func in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < BOARD_SIZE \
		and grid_pos.y >= 0 and grid_pos.y < BOARD_SIZE
