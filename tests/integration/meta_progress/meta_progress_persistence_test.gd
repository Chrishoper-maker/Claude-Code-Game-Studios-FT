# MetaProgress 文件往返（user:// 临时文件）。
extends GdUnitTestSuite

const TMP := "user://test_meta_persist.json"

func before_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = TMP
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

func after_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = "user://meta.json"
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

func test_save_then_load_roundtrip() -> void:
	var ids: Array[String] = ["crew_gunner_03", "crew_medic_02"]
	MetaProgress.unlocked_crew_ids = ids
	MetaProgress.save_progress()
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress.load_progress()
	assert_array(MetaProgress.unlocked_crew_ids).contains_exactly(["crew_gunner_03", "crew_medic_02"])

func test_load_missing_file_yields_empty() -> void:
	var ids: Array[String] = ["x"]
	MetaProgress.unlocked_crew_ids = ids
	MetaProgress.load_progress()   # TMP 已确保不存在
	assert_int(MetaProgress.unlocked_crew_ids.size()).is_equal(0)
