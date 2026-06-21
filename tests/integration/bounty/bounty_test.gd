# 悬赏成长集成：末岛胜触发解锁 + 招募池纳入已解锁 unlockable。
extends GdUnitTestSuite

const TMP := "user://test_bounty.json"

func before_test() -> void:
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = TMP
	RunManager.start_run()
	RunManager._rng.seed = 20260621

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = "user://meta.json"
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

# AC-4：末岛胜利解锁顺序首位。
func test_final_island_win_unlocks_next() -> void:
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	EventBus.battle_won.emit()
	assert_int(MetaProgress.unlocked_crew_ids.size()).is_equal(1)
	assert_str(MetaProgress.unlocked_crew_ids[0]).is_equal(MetaProgress.get_unlock_order()[0])

# AC-6：非末岛胜不解锁。
func test_nonfinal_win_does_not_unlock() -> void:
	RunManager.current_island_index = 0
	EventBus.battle_won.emit()
	assert_int(MetaProgress.unlocked_crew_ids.size()).is_equal(0)

# AC-6：战败不解锁。
func test_loss_does_not_unlock() -> void:
	RunManager.current_island_index = 2
	EventBus.battle_lost.emit()
	assert_int(MetaProgress.unlocked_crew_ids.size()).is_equal(0)

# AC-5：未解锁的 unlockable 不进 offer。
func test_locked_unlockable_not_offered() -> void:
	var offers := RunManager.get_recruit_offers()
	for o in offers:
		assert_str((o as CrewDefinition).recruit_pool_tier).is_not_equal("unlockable")

# AC-5：解锁后可进 offer（排除全部 pool 后只剩它）。
func test_unlocked_unlockable_can_be_offered() -> void:
	var target := "crew_gunner_03"
	var ids: Array[String] = [target]
	MetaProgress.unlocked_crew_ids = ids
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "pool":
			RunManager._excluded_offers.append((def as CrewDefinition).id)
	var offers := RunManager.get_recruit_offers()
	var found := false
	for o in offers:
		if (o as CrewDefinition).id == target:
			found = true
	assert_bool(found).is_true()
