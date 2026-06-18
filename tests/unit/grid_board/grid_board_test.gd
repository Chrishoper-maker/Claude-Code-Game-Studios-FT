# GridBoard 空间逻辑测试（grid-board-system GDD 公式 1-3 + 占用 + 4向BFS + 8向相邻）。
# TDD：先于实现写就。
extends GdUnitTestSuite

const EMPTY := -1

func _board() -> GridBoard:
	return auto_free(GridBoard.new())

# ── 公式 1：越界 ──
func test_in_bounds() -> void:
	var b := _board()
	assert_bool(b.in_bounds(Vector2i(0, 0))).is_true()
	assert_bool(b.in_bounds(Vector2i(7, 7))).is_true()
	assert_bool(b.in_bounds(Vector2i(8, 0))).is_false()
	assert_bool(b.in_bounds(Vector2i(0, -1))).is_false()

# ── 公式 2：切比雪夫 / 相邻（八向）──
func test_chebyshev_and_adjacency() -> void:
	assert_int(GridBoard.chebyshev(Vector2i(3, 3), Vector2i(4, 4))).is_equal(1)
	assert_int(GridBoard.chebyshev(Vector2i(3, 3), Vector2i(5, 3))).is_equal(2)
	assert_bool(GridBoard.is_adjacent(Vector2i(3, 3), Vector2i(4, 4))).is_true()   # 斜格相邻
	assert_bool(GridBoard.is_adjacent(Vector2i(3, 3), Vector2i(5, 3))).is_false()
	assert_bool(GridBoard.is_adjacent(Vector2i(3, 3), Vector2i(3, 3))).is_false()  # 同格不相邻

func test_manhattan() -> void:
	assert_int(GridBoard.manhattan(Vector2i(3, 3), Vector2i(4, 4))).is_equal(2)
	assert_int(GridBoard.manhattan(Vector2i(1, 1), Vector2i(1, 4))).is_equal(3)

# ── 占用 ──
func test_place_and_get_cell() -> void:
	var b := _board()
	b.place_unit(5, Vector2i(2, 2))
	assert_int(b.get_cell(Vector2i(2, 2))).is_equal(5)
	assert_int(b.get_cell(Vector2i(0, 0))).is_equal(EMPTY)

func test_is_empty() -> void:
	var b := _board()
	assert_bool(b.is_empty(Vector2i(0, 0))).is_true()
	b.place_unit(1, Vector2i(0, 0))
	assert_bool(b.is_empty(Vector2i(0, 0))).is_false()
	assert_bool(b.is_empty(Vector2i(9, 9))).is_false()   # 越界非空（不可进入）

func test_remove_unit_clears_cell() -> void:
	var b := _board()
	b.place_unit(7, Vector2i(3, 3))
	b.remove_unit(7)
	assert_int(b.get_cell(Vector2i(3, 3))).is_equal(EMPTY)
	assert_bool(b.is_empty(Vector2i(3, 3))).is_true()

func test_forced_move_unit() -> void:
	var b := _board()
	b.place_unit(9, Vector2i(2, 2))
	b.forced_move_unit(9, Vector2i(4, 4))
	assert_int(b.get_cell(Vector2i(2, 2))).is_equal(EMPTY)
	assert_int(b.get_cell(Vector2i(4, 4))).is_equal(9)
	assert_vector(b.get_unit_pos(9)).is_equal(Vector2i(4, 4))

# ── 相邻占用查询（八向，返回 unit_id 列表）──
func test_get_adjacents_returns_occupant_ids() -> void:
	var b := _board()
	b.place_unit(1, Vector2i(2, 3))   # 正交邻
	b.place_unit(2, Vector2i(4, 4))   # 斜邻
	b.place_unit(3, Vector2i(3, 5))   # 非邻（cheb=2）
	var ids := b.get_adjacents(Vector2i(3, 3))
	assert_array(ids).contains([1, 2])
	assert_array(ids).not_contains([3])

# ── 公式 3：攻击范围（双度量）──
func test_in_attack_range_melee_uses_chebyshev() -> void:
	var b := _board()
	assert_bool(b.in_attack_range(Vector2i(3, 3), Vector2i(4, 4), 1)).is_true()   # 斜格近战可达
	assert_bool(b.in_attack_range(Vector2i(3, 3), Vector2i(5, 3), 1)).is_false()  # cheb=2 超出

func test_in_attack_range_ranged_uses_manhattan() -> void:
	var b := _board()
	assert_bool(b.in_attack_range(Vector2i(3, 3), Vector2i(4, 4), 2)).is_true()   # manhattan=2 ≤ 2
	assert_bool(b.in_attack_range(Vector2i(3, 3), Vector2i(5, 5), 2)).is_false()  # manhattan=4 > 2

func test_in_attack_range_is_symmetric() -> void:
	var b := _board()
	var a := Vector2i(3, 3)
	var c := Vector2i(5, 4)
	assert_bool(b.in_attack_range(a, c, 3)).is_equal(b.in_attack_range(c, a, 3))

# ── 4向BFS 可达 ──
func test_reachable_range_1_is_four_orthogonal() -> void:
	var b := _board()
	var cells := b.get_reachable_cells(Vector2i(3, 3), 1)
	assert_array(cells).contains([Vector2i(2, 3), Vector2i(4, 3), Vector2i(3, 2), Vector2i(3, 4)])
	assert_array(cells).not_contains([Vector2i(4, 4)])         # 斜向非 4 向可达
	assert_array(cells).not_contains([Vector2i(3, 3)])         # 不含起点
	assert_int(cells.size()).is_equal(4)

func test_reachable_blocked_by_occupied() -> void:
	var b := _board()
	b.place_unit(1, Vector2i(4, 3))   # 挡住右
	var cells := b.get_reachable_cells(Vector2i(3, 3), 1)
	assert_array(cells).not_contains([Vector2i(4, 3)])         # 占用格不可进入
	assert_int(cells.size()).is_equal(3)

func test_reachable_respects_bounds() -> void:
	var b := _board()
	var cells := b.get_reachable_cells(Vector2i(0, 0), 1)      # 角格只有 2 个正交邻在界内
	assert_array(cells).contains([Vector2i(1, 0), Vector2i(0, 1)])
	assert_int(cells.size()).is_equal(2)

func test_reachable_range_2_expands() -> void:
	var b := _board()
	var cells := b.get_reachable_cells(Vector2i(3, 3), 2)
	# 曼哈顿 ≤2 的 4 向可达格（菱形去起点）：range1 的 4 个 + 第二圈 8 个 = 12
	assert_int(cells.size()).is_equal(12)
	assert_array(cells).contains([Vector2i(3, 5), Vector2i(1, 3), Vector2i(4, 4)])
