# 套装计数器：件数 / 主套（并列字典序）/ 激活档位。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()

func test_set_counts_groups_by_set_id() -> void:
	RunManager._roster_equipment["c1"] = {
		0: "eq_ironwall_mainweapon",
		3: "eq_ironwall_armor",
		2: "eq_berserker_head",
	}
	var counts := RunManager.get_set_counts("c1")
	assert_int(int(counts.get("set_ironwall", 0))).is_equal(2)
	assert_int(int(counts.get("set_berserker", 0))).is_equal(1)

func test_dominant_set_is_most_held() -> void:
	RunManager._roster_equipment["c1"] = {
		0: "eq_ironwall_mainweapon",
		3: "eq_ironwall_armor",
		2: "eq_berserker_head",
	}
	assert_str(RunManager.get_dominant_set("c1")).is_equal("set_ironwall")

func test_dominant_set_tie_breaks_lexicographically() -> void:
	RunManager._roster_equipment["c1"] = {
		0: "eq_ironwall_mainweapon",
		2: "eq_berserker_head",
	}
	# 并列 1:1 → 字典序最小 set_berserker < set_ironwall
	assert_str(RunManager.get_dominant_set("c1")).is_equal("set_berserker")

func test_dominant_set_empty_when_no_equipment() -> void:
	assert_str(RunManager.get_dominant_set("nobody")).is_equal("")

func test_active_tier_thresholds() -> void:
	var slots: Dictionary = {}
	for i in range(6):
		slots[i] = ["eq_ironwall_mainweapon", "eq_ironwall_offweapon", "eq_ironwall_head", "eq_ironwall_armor", "eq_ironwall_gloves", "eq_ironwall_legs"][i]
	RunManager._roster_equipment["c1"] = slots
	assert_int(RunManager.get_active_set_tier("c1", "set_ironwall")).is_equal(6)
	assert_int(RunManager.get_active_set_tier("c1", "set_berserker")).is_equal(0)
