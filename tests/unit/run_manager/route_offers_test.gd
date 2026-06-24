# 选航候选生成（子项目①）：数量 / tier 过滤 / 不重复 / 降级 / 确定性。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 20260624

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route = RunManager._default_goto_route

# 首岛（next_idx=0）→ 目标 tier [1]，3 张全 island_tier 1。
func test_first_island_offers_three_tier1_maps() -> void:
	RunManager.current_island_index = -1
	var offers := RunManager.get_route_offers()
	assert_int(offers.size()).is_equal(3)
	for o in offers:
		assert_int((o as MapDefinition).island_tier).is_equal(1)

# 候选写入 _last_route_offers（供 confirm_route 校验）。
func test_offers_recorded_in_last_route_offers() -> void:
	RunManager.current_island_index = -1
	var offers := RunManager.get_route_offers()
	assert_int(RunManager._last_route_offers.size()).is_equal(offers.size())
	for o in offers:
		assert_bool(RunManager._last_route_offers.has((o as MapDefinition).map_id)).is_true()

# 本 run 已访问的图不再作为候选（不重复，池足时）。
func test_visited_maps_excluded_when_pool_allows() -> void:
	RunManager.current_island_index = -1
	var first := RunManager.get_route_offers()
	var visited_id := (first[0] as MapDefinition).map_id
	RunManager._visited_map_ids.append(visited_id)
	var second := RunManager.get_route_offers()
	for o in second:
		assert_str((o as MapDefinition).map_id).is_not_equal(visited_id)

# 目标 tier 候选不足 3 时优雅降级补足（末岛 next_idx=4 → 目标 [3] 仅 2 张 → 补到 3）。
func test_degrades_when_target_tier_insufficient() -> void:
	RunManager.current_island_index = 3   # next_idx = 4
	var offers := RunManager.get_route_offers()
	assert_int(offers.size()).is_equal(3)

# 确定性：同 seed + 同 visited 重复调用得同结果（续航复现）。
func test_offers_deterministic_for_same_seed() -> void:
	RunManager.current_island_index = -1
	RunManager._rng.seed = 999
	var a := RunManager.get_route_offers()
	RunManager._rng.seed = 999
	var b := RunManager.get_route_offers()
	assert_int(a.size()).is_equal(b.size())
	for i in range(a.size()):
		assert_str((a[i] as MapDefinition).map_id).is_equal((b[i] as MapDefinition).map_id)

# 目标 tier 映射表（纯函数）。
func test_target_tiers_mapping() -> void:
	assert_array(RunManager._target_tiers_for_island(0)).is_equal([1])
	assert_array(RunManager._target_tiers_for_island(1)).is_equal([1, 2])
	assert_array(RunManager._target_tiers_for_island(2)).is_equal([1, 2])
	assert_array(RunManager._target_tiers_for_island(3)).is_equal([2, 3])
	assert_array(RunManager._target_tiers_for_island(4)).is_equal([3])
