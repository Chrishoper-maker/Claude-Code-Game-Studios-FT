# RunManager 状态机单元测试（ADR-0004 验证条 2/4 + ADR-0002 win 分支）。
# ✅ 实测通过（GdUnit4 v6.1.3 / Godot 4.6.3，2026-06-19）：7/7 PASSED。
# 仅测无场景依赖的纯逻辑——confirm_deploy/_on_battle_won 的非终局分支会调
#   SceneManager.goto_*（assert 未赋值场景）故不在此测。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager.start_run()   # 复位：DEPLOYING + 清 roster/_downed/island

func test_start_run_enters_deploying_phase() -> void:
	assert_str(RunManager.current_phase).is_equal("DEPLOYING")

func test_start_run_resets_roster_and_island() -> void:
	assert_int(RunManager.roster.size()).is_equal(0)
	assert_int(RunManager.current_island_index).is_equal(-1)

# String 门面映射（ADR-0004 验证条 2）。_set_run_phase 仅发信号、无场景依赖。
func test_facade_maps_island_battle_to_BATTLE() -> void:
	RunManager._set_run_phase(RunManager.RunPhase.RUN_ISLAND_BATTLE)
	assert_str(RunManager.current_phase).is_equal("BATTLE")

func test_facade_maps_recruiting_to_RECRUITING() -> void:
	RunManager._set_run_phase(RunManager.RunPhase.RUN_RECRUITING)
	assert_str(RunManager.current_phase).is_equal("RECRUITING")

func test_facade_maps_run_end() -> void:
	RunManager._set_run_phase(RunManager.RunPhase.RUN_END)
	assert_str(RunManager.current_phase).is_equal("RUN_END")

# 末岛胜利 → RUN_END（ADR-0002；此分支不调 SceneManager，可测）。
func test_battle_won_at_final_island_ends_run() -> void:
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	RunManager._on_battle_won()
	assert_str(RunManager.current_phase).is_equal("RUN_END")

# 阵亡去重：同一 unit_id 多次只记一次（R1 公式排除集）。
func test_crew_downed_recorded_once() -> void:
	RunManager._on_crew_member_downed(7)
	RunManager._on_crew_member_downed(7)
	assert_int(RunManager._downed_this_run.size()).is_equal(1)
	assert_bool(RunManager._downed_this_run.has(7)).is_true()
