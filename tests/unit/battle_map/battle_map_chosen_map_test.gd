# battle_map.load_map 读 RunManager 选定的地图（子项目①）。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route = func() -> void: pass
	RunManager.start_run()
	RunManager._chosen_map_id = ""

func after_test() -> void:
	RunManager._chosen_map_id = ""
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route = RunManager._default_goto_route

func _bm() -> BattleMap: return auto_free(BattleMap.new())
func _gb() -> GridBoard: return auto_free(GridBoard.new())
func _tm() -> TurnManager: return auto_free(TurnManager.new())

# AC-5：选定图 → load_map 加载该图并就绪（map_loaded 携带其 map_id）。
func test_load_map_uses_chosen_map() -> void:
	RunManager._chosen_map_id = "battle_map_006"
	var bm := _bm()
	bm.setup(_gb(), _tm())
	var loaded_id := [""]
	EventBus.map_loaded.connect(func(mid: String) -> void: loaded_id[0] = mid)
	bm.load_map(0)
	assert_str(loaded_id[0]).is_equal("battle_map_006")

# AC-5：未选图（空）→ 回退 battle_map_001。
func test_load_map_falls_back_when_unchosen() -> void:
	RunManager._chosen_map_id = ""
	var bm := _bm()
	bm.setup(_gb(), _tm())
	var loaded_id := [""]
	EventBus.map_loaded.connect(func(mid: String) -> void: loaded_id[0] = mid)
	bm.load_map(0)
	assert_str(loaded_id[0]).is_equal("battle_map_001")
