# RunManager 状态机单元测试（ADR-0004 验证条 2/4 + ADR-0002 win 分支）。
# ✅ 实测通过（GdUnit4 v6.1.3 / Godot 4.6.3，2026-06-19）：7/7 PASSED。
# 仅测无场景依赖的纯逻辑——confirm_deploy/_on_battle_won 的非终局分支会调
#   SceneManager.goto_*（assert 未赋值场景）故不在此测。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass   # 防止单测真的切场景
	RunManager._goto_route = func() -> void: pass
	MetaProgress.unlocked_crew_ids.clear()
	RunManager.start_run()        # 复位：DEPLOYING + 填起始编制 + 清 offer/pending
	RunManager._rng.seed = 20260620

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route = RunManager._default_goto_route

func test_start_run_enters_deploying_phase() -> void:
	assert_str(RunManager.current_phase).is_equal("DEPLOYING")

func test_start_run_resets_island_index() -> void:
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

# 永久死亡：同一持久 crew id 多次只记一次，且永久移出 roster + 加入招募排除。
func test_crew_downed_recorded_once() -> void:
	var first_id: String = (RunManager.roster[0] as CrewDefinition).id
	var before := RunManager.roster.size()
	RunManager._on_crew_member_downed(first_id)
	RunManager._on_crew_member_downed(first_id)
	assert_int(RunManager._downed_this_run.size()).is_equal(1)
	assert_bool(RunManager._downed_this_run.has(first_id)).is_true()
	assert_int(RunManager.roster.size()).is_equal(before - 1)
	assert_bool(RunManager._excluded_offers.has(first_id)).is_true()

# 阵亡者不再被招募（防复活）。
func test_downed_crew_not_offered_again() -> void:
	var pool_id := "crew_gunner_01"
	RunManager._on_crew_member_downed(pool_id)
	var offers := RunManager.get_recruit_offers()
	for o in offers:
		assert_str((o as CrewDefinition).id).is_not_equal(pool_id)

# 阵亡填充"待通知"集合；clear/start_run 清空。
func test_downed_fills_and_clears_pending_notice() -> void:
	var id: String = (RunManager.roster[0] as CrewDefinition).id
	RunManager._on_crew_member_downed(id)
	assert_bool(RunManager.get_pending_downed_notice().has(id)).is_true()
	RunManager.clear_downed_notice()
	assert_int(RunManager.get_pending_downed_notice().size()).is_equal(0)

func test_start_run_clears_pending_notice() -> void:
	RunManager._on_crew_member_downed((RunManager.roster[0] as CrewDefinition).id)
	RunManager.start_run()
	assert_int(RunManager.get_pending_downed_notice().size()).is_equal(0)

func test_pending_notice_deduped() -> void:
	var id: String = (RunManager.roster[0] as CrewDefinition).id
	RunManager._on_crew_member_downed(id)
	RunManager._on_crew_member_downed(id)
	assert_int(RunManager.get_pending_downed_notice().size()).is_equal(1)

func test_get_downed_this_run_returns_fallen() -> void:
	var id: String = (RunManager.roster[0] as CrewDefinition).id
	RunManager._on_crew_member_downed(id)
	assert_bool(RunManager.get_downed_this_run().has(id)).is_true()

func test_start_run_fills_roster_with_starting_crew() -> void:
	# Arrange/Act done in before_test
	# Assert: roster 全为 starting tier，且数量 == 注册表中 starting crew 数
	var expected := 0
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "starting":
			expected += 1
	assert_int(RunManager.roster.size()).is_equal(expected)
	assert_int(expected).is_greater_equal(1)
	for c in RunManager.roster:
		assert_str((c as CrewDefinition).recruit_pool_tier).is_equal("starting")

func test_start_run_resets_run_state() -> void:
	RunManager._excluded_offers.append("x")
	RunManager._last_offers.append("y")
	RunManager.pending_deploy.append(null)
	RunManager.last_run_won = true
	RunManager.start_run()
	assert_int(RunManager._excluded_offers.size()).is_equal(0)
	assert_int(RunManager._last_offers.size()).is_equal(0)
	assert_int(RunManager.pending_deploy.size()).is_equal(0)
	assert_int(RunManager.current_island_index).is_equal(-1)
	assert_str(RunManager.current_phase).is_equal("DEPLOYING")
	assert_bool(RunManager.last_run_won).is_false()

func test_battle_won_non_final_enters_recruiting() -> void:
	RunManager.current_island_index = 0   # 0+1 < 5 → 非末岛
	RunManager._on_battle_won()
	assert_str(RunManager.current_phase).is_equal("RECRUITING")

func test_battle_won_final_sets_last_run_won_true() -> void:
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	RunManager._on_battle_won()
	assert_str(RunManager.current_phase).is_equal("RUN_END")
	assert_bool(RunManager.last_run_won).is_true()

func test_battle_lost_ends_run_with_loss() -> void:
	var monitor := monitor_signals(EventBus, false)  # false = 不 auto_free autoload
	RunManager.current_island_index = 2
	RunManager._on_battle_lost()
	assert_str(RunManager.current_phase).is_equal("RUN_END")
	assert_bool(RunManager.last_run_won).is_false()
	await assert_signal(monitor).is_emitted("run_completed", [false, 3, RunManager.roster])

func test_offers_are_pool_tier_and_exclude_roster() -> void:
	var roster_ids: Dictionary = {}
	for c in RunManager.roster:
		roster_ids[(c as CrewDefinition).id] = true
	var offers := RunManager.get_recruit_offers()
	assert_int(offers.size()).is_less_equal(RunManager.RECRUIT_OFFER_COUNT)
	for o in offers:
		assert_str((o as CrewDefinition).recruit_pool_tier).is_equal("pool")
		assert_bool(roster_ids.has((o as CrewDefinition).id)).is_false()

func test_offers_have_distinct_unit_classes() -> void:
	var offers := RunManager.get_recruit_offers()
	var seen: Dictionary = {}
	for o in offers:
		var cls := (o as CrewDefinition).unit_class
		assert_bool(seen.has(cls)).is_false()
		seen[cls] = true

func test_offers_exclude_excluded_ids() -> void:
	var first := RunManager.get_recruit_offers()
	# 把首批全部塞入排除集，再抽：不得再出现这些 id
	for o in first:
		RunManager._excluded_offers.append((o as CrewDefinition).id)
	var second := RunManager.get_recruit_offers()
	for o in second:
		assert_bool(RunManager._excluded_offers.has((o as CrewDefinition).id)).is_false()

func test_offers_empty_when_pool_exhausted() -> void:
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "pool":
			RunManager._excluded_offers.append((def as CrewDefinition).id)
	var offers := RunManager.get_recruit_offers()
	assert_int(offers.size()).is_equal(0)

func test_confirm_recruit_adds_choice_excludes_rest() -> void:
	var offers := RunManager.get_recruit_offers()
	assert_int(offers.size()).is_greater_equal(2)   # 需≥2 才能验「其余被排除」
	var chosen := (offers[0] as CrewDefinition).id
	var rest := (offers[1] as CrewDefinition).id
	var before := RunManager.roster.size()
	RunManager.confirm_recruit(chosen)
	assert_int(RunManager.roster.size()).is_equal(before + 1)
	var ids: Array[String] = []
	for c in RunManager.roster:
		ids.append((c as CrewDefinition).id)
	assert_bool(ids.has(chosen)).is_true()
	assert_bool(RunManager._excluded_offers.has(rest)).is_true()
	assert_str(RunManager.current_phase).is_equal("DEPLOYING")

func test_confirm_deploy_builds_pending_and_advances_island() -> void:
	# Arrange: roster 已含起始编制（before_test）
	var ids: Array[String] = []
	for c in RunManager.roster:
		ids.append((c as CrewDefinition).id)
	var island_before := RunManager.current_island_index
	# Act
	RunManager.confirm_deploy(ids)
	# Assert
	assert_int(RunManager.get_pending_deploy().size()).is_equal(ids.size())
	assert_int(RunManager.current_island_index).is_equal(island_before + 1)
	assert_str(RunManager.current_phase).is_equal("BATTLE")

func test_confirm_deploy_filters_to_selected_ids() -> void:
	var all_ids: Array[String] = []
	for c in RunManager.roster:
		all_ids.append((c as CrewDefinition).id)
	assert_int(all_ids.size()).is_greater_equal(1)
	var subset: Array = [all_ids[0]]
	RunManager.confirm_deploy(subset)
	assert_int(RunManager.get_pending_deploy().size()).is_equal(1)
	assert_str((RunManager.get_pending_deploy()[0] as CrewDefinition).id).is_equal(all_ids[0])
