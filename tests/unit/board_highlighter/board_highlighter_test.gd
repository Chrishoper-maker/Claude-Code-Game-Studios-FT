extends GdUnitTestSuite

func test_show_then_clear_does_not_crash() -> void:
	var bh: BoardHighlighter = auto_free(BoardHighlighter.new())
	add_child(bh)
	bh.show_cells([Vector2i(0, 0), Vector2i(1, 1)], Color("#22FF66"))
	bh.clear()
	assert_object(bh).is_not_null()
