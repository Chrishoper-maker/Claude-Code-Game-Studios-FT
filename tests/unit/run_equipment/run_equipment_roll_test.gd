extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._rng.seed = 12345   # 确定性

func test_rolls_exactly_8() -> void:
	var rolled := RunManager.roll_recruit_equipment()
	assert_int(rolled.size()).is_equal(8)

func test_same_slot_capped_at_2() -> void:
	var rolled := RunManager.roll_recruit_equipment()
	var slot_counts: Dictionary = {}
	for eq in rolled:
		slot_counts[eq.slot] = int(slot_counts.get(eq.slot, 0)) + 1
	for s in slot_counts:
		assert_int(int(slot_counts[s])).is_less_equal(2)

func test_deterministic_same_seed_same_roll() -> void:
	RunManager._rng.seed = 777
	var a := RunManager.roll_recruit_equipment()
	RunManager._rng.seed = 777
	var b := RunManager.roll_recruit_equipment()
	var ida: Array[String] = []
	var idb: Array[String] = []
	for e in a: ida.append(e.id)
	for e in b: idb.append(e.id)
	assert_array(ida).is_equal(idb)

func test_weighted_distribution_skews_common() -> void:
	# 大样本：普通(0)占比应远高于传奇(4)
	var counts := {0:0, 1:0, 2:0, 3:0, 4:0}
	RunManager._rng.seed = 1
	for n in 200:
		for eq in RunManager.roll_recruit_equipment():
			counts[eq.rarity] += 1
	assert_int(counts[0]).is_greater(counts[4])
	assert_int(counts[1]).is_greater(counts[4])
