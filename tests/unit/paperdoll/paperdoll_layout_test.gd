# 人形纸娃娃：_build_paperdoll 产出含 3 列 GridContainer（12 格）的身体布局。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()

func _crew_id() -> String:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition:
			return (d as CrewDefinition).id
	return ""

func _find_grid(node: Node) -> GridContainer:
	for ch in node.get_children():
		if ch is GridContainer:
			return ch as GridContainer
		var r := _find_grid(ch)
		if r != null:
			return r
	return null

func test_paperdoll_has_three_column_grid_with_twelve_cells() -> void:
	var cid := _crew_id()
	RunManager._roster_equipment[cid] = {2: "eq_ironwall_head"}   # 头槽有装备
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var doll := route._build_paperdoll(cid)
	add_child(doll)            # 进树便于检索（auto_free route 已托管）
	var grid := _find_grid(doll)
	assert_object(grid).is_not_null()
	assert_int(grid.columns).is_equal(3)
	assert_int(grid.get_child_count()).is_equal(12)
	doll.free()
