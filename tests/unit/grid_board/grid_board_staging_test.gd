# GridBoard.get_attack_staging_cells 测试（grid-board 接口；enemy-ai 决策树用）。
# 可移动后攻击目标的最优格集合 = 移动范围内可达 且 目标进入攻击范围 的空格。
# TDD：先于实现写就。
extends GdUnitTestSuite

func _gb() -> GridBoard:
	return auto_free(GridBoard.new())

# 移动范围内可达且目标进入近战范围的格
func test_staging_within_move_and_attack_range() -> void:
	var gb := _gb()
	# mover (0,0) move 2，目标 (0,3) 近战 range1 → (0,2) 可达且切比雪夫相邻目标
	var staging := gb.get_attack_staging_cells(Vector2i(0, 0), 2, Vector2i(0, 3), 1)
	assert_array(staging).contains([Vector2i(0, 2)])

# 目标不可达时返回空
func test_staging_empty_when_unreachable() -> void:
	var gb := _gb()
	var staging := gb.get_attack_staging_cells(Vector2i(0, 0), 1, Vector2i(7, 7), 1)
	assert_array(staging).is_empty()

# 确定性排序（col*8+row 升序）
func test_staging_sorted_deterministically() -> void:
	var gb := _gb()
	# mover (3,3) move 2，目标 (3,3) 自身... 用远程 range 让多格满足
	var staging := gb.get_attack_staging_cells(Vector2i(3, 3), 2, Vector2i(3, 3), 2)
	# 断言已按 x*8+y 升序
	for i in range(1, staging.size()):
		var prev: Vector2i = staging[i - 1]
		var cur: Vector2i = staging[i]
		assert_bool((prev.x * 8 + prev.y) < (cur.x * 8 + cur.y)).is_true()
	assert_bool(staging.size() > 1).is_true()
