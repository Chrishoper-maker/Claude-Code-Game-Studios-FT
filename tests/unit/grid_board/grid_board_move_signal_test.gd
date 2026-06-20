extends GdUnitTestSuite

func test_forced_move_unit_emits_unit_moved() -> void:
	var gb: GridBoard = auto_free(GridBoard.new())
	gb.place_unit(7, Vector2i(1, 1))
	var events: Array = []
	var cb := func(id: int, from_pos: Vector2i, to_pos: Vector2i) -> void:
		events.append([id, from_pos, to_pos])
	EventBus.unit_moved.connect(cb)
	gb.forced_move_unit(7, Vector2i(1, 2))
	EventBus.unit_moved.disconnect(cb)
	assert_int(events.size()).is_equal(1)
	assert_int(events[0][0]).is_equal(7)
	assert_vector(events[0][1]).is_equal(Vector2i(1, 1))
	assert_vector(events[0][2]).is_equal(Vector2i(1, 2))
