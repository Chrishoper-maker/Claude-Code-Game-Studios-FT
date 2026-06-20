# GridCoordMapper 测试（ADR-0006：全项目唯一逻辑格↔世界坐标映射）。
# 纯静态无状态工具。TDD：先于实现写就。
extends GdUnitTestSuite

func test_grid_to_world_origin() -> void:
	assert_vector(GridCoordMapper.grid_to_world(Vector2i(0, 0))).is_equal(Vector3(0, 0, 0))

# (col,row) → (col*CELL_SIZE, 0, row*CELL_SIZE)，CELL_SIZE=2.0
func test_grid_to_world_scales_by_cell_size() -> void:
	assert_vector(GridCoordMapper.grid_to_world(Vector2i(3, 5))).is_equal(Vector3(6, 0, 10))

# 世界 → 逻辑格（roundi 拾取）
func test_world_to_grid_rounds() -> void:
	assert_vector(GridCoordMapper.world_to_grid(Vector3(5.8, 0, 9.9))).is_equal(Vector2i(3, 5))

func test_roundtrip() -> void:
	var g := Vector2i(7, 2)
	assert_vector(GridCoordMapper.world_to_grid(GridCoordMapper.grid_to_world(g))).is_equal(g)

# 棋盘中心 = ((8-1)/2 * 2) = 7 → (7,0,7)
func test_board_center() -> void:
	assert_vector(GridCoordMapper.board_center()).is_equal(Vector3(7, 0, 7))
