# DeployScreen 手动选人集成测试（子项目 B）：实例化 RouteScene 白盒中枢，
# 经 _deploy_buttons[id].button_pressed 赋值驱动真实 toggled 接线（无头安全，非 InputEvent）。
# 导航接缝 stub 为 no-op 防真切场景；roster>4 经追加 pool crew 构造。
# Task 8 修复：start_run 现进 CHARTING；需先 confirm_route 驱到 DEPLOYING，
# 再实例化 RouteScene，令 _ready 命中默认分支进部署选人界面。
extends GdUnitTestSuite

const POOL_IDS: Array[String] = [
	"crew_swordsman_02", "crew_gunner_01", "crew_bulwark_02", "crew_medic_01",
	"crew_navigator_01", "crew_musician_01", "crew_gunner_02", "crew_swordsman_03",
]

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 20260621

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

func _grow_roster_to(n: int) -> void:
	for pid in POOL_IDS:
		if RunManager.roster.size() >= n:
			break
		var def := UnitDataManager.get_unit(pid)
		if def is CrewDefinition:
			RunManager.roster.append(def as CrewDefinition)

func _roster_ids() -> Array[String]:
	var ids: Array[String] = []
	for c in RunManager.get_roster():
		ids.append(c.id)
	return ids

func _btn(route: RouteScene, crew_id: String) -> Button:
	return route._deploy_buttons[crew_id] as Button

# 将 RunManager 从 CHARTING 显式驱到 DEPLOYING（选第一个候选地图）。
# Task 8 后 start_run 进 CHARTING；DeployScreen 测试须先过选航才能到部署界面。
func _advance_to_deploying() -> void:
	var offers := RunManager.get_route_offers()
	RunManager.confirm_route((offers[0] as MapDefinition).map_id)

# AC-1：roster ≤ DEPLOY_LIMIT 自动全员，不展示界面。
func test_ac1_small_roster_auto_deploys() -> void:
	_advance_to_deploying()
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)   # _ready: DEPLOYING → _enter_deploy → roster=2≤4 → auto
	assert_str(RunManager.current_phase).is_equal("BATTLE")
	assert_int(RunManager.get_pending_deploy().size()).is_equal(2)
	assert_int(route._deploy_buttons.size()).is_equal(0)

# AC-2：roster > DEPLOY_LIMIT 展示选人界面，未自动确认。
func test_ac2_large_roster_shows_selection() -> void:
	_grow_roster_to(5)
	_advance_to_deploying()
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	assert_int(route._deploy_buttons.size()).is_equal(5)
	assert_bool(route._deploy_confirm_button.disabled).is_true()
	assert_str(RunManager.current_phase).is_equal("DEPLOYING")

# AC-3：选满 4 人确认 → confirm_deploy 收到那 4 个 id。
func test_ac3_select_four_and_confirm() -> void:
	_grow_roster_to(5)
	_advance_to_deploying()
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var ids := _roster_ids()
	var chosen: Array[String] = [ids[0], ids[1], ids[2], ids[3]]
	for cid in chosen:
		_btn(route, cid).button_pressed = true
	route._on_deploy_confirm()
	assert_str(RunManager.current_phase).is_equal("BATTLE")
	assert_int(RunManager.get_pending_deploy().size()).is_equal(4)
	var pending_ids: Array[String] = []
	for c in RunManager.get_pending_deploy():
		pending_ids.append(c.id)
	for cid in chosen:
		assert_bool(pending_ids.has(cid)).is_true()

# AC-4：选满 4 后第 5 个被回弹拒绝。
func test_ac4_fifth_selection_rejected() -> void:
	_grow_roster_to(6)
	_advance_to_deploying()
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var ids := _roster_ids()
	for j in 4:
		_btn(route, ids[j]).button_pressed = true
	_btn(route, ids[4]).button_pressed = true   # 第 5 个
	assert_int(route._selected_ids.size()).is_equal(4)
	assert_bool(_btn(route, ids[4]).button_pressed).is_false()
	assert_bool(route._selected_ids.has(ids[4])).is_false()

# AC-5：确认键随选择数启用/禁用 + 状态标签。
func test_ac5_confirm_tracks_selection() -> void:
	_grow_roster_to(5)
	_advance_to_deploying()
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var first: String = _roster_ids()[0]
	assert_bool(route._deploy_confirm_button.disabled).is_true()
	assert_str(route._deploy_status_label.text).is_equal("已选 0/4")
	_btn(route, first).button_pressed = true
	assert_bool(route._deploy_confirm_button.disabled).is_false()
	assert_str(route._deploy_status_label.text).is_equal("已选 1/4")
	_btn(route, first).button_pressed = false
	assert_bool(route._deploy_confirm_button.disabled).is_true()
	assert_str(route._deploy_status_label.text).is_equal("已选 0/4")

# AC-6：子集部署（少于满编）成功。
func test_ac6_subset_deploy() -> void:
	_grow_roster_to(5)
	_advance_to_deploying()
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var ids := _roster_ids()
	_btn(route, ids[0]).button_pressed = true
	_btn(route, ids[1]).button_pressed = true
	route._on_deploy_confirm()
	assert_str(RunManager.current_phase).is_equal("BATTLE")
	assert_int(RunManager.get_pending_deploy().size()).is_equal(2)
