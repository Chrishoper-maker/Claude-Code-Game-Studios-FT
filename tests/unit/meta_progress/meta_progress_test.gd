# MetaProgress 解锁逻辑 + 序列化（写入注入的临时 _save_path，after_test 清理）。
extends GdUnitTestSuite

const TMP := "user://test_meta_unit.json"

func before_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = TMP

func after_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = "user://meta.json"
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

func test_unlock_next_follows_lexicographic_order() -> void:
	var order := MetaProgress.get_unlock_order()
	assert_int(order.size()).is_greater_equal(3)
	assert_str(MetaProgress.unlock_next()).is_equal(order[0])
	assert_bool(MetaProgress.is_unlocked(order[0])).is_true()
	assert_str(MetaProgress.unlock_next()).is_equal(order[1])

func test_unlock_next_empty_when_all_unlocked() -> void:
	for _i in MetaProgress.get_unlock_order().size():
		MetaProgress.unlock_next()
	var before := MetaProgress.unlocked_crew_ids.size()
	assert_str(MetaProgress.unlock_next()).is_equal("")
	assert_int(MetaProgress.unlocked_crew_ids.size()).is_equal(before)

func test_to_from_dict_roundtrip() -> void:
	var ids: Array[String] = ["a", "b"]
	MetaProgress.unlocked_crew_ids = ids
	var d := MetaProgress.to_dict()
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress.from_dict(d)
	assert_array(MetaProgress.unlocked_crew_ids).contains_exactly(["a", "b"])
