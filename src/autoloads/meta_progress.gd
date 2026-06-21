# 跨 run 持久化的 meta 解锁状态（autoload；不被 start_run 清除）。悬赏成长唯一持久层。
# 只存"已解锁 unlockable 船员 id 集"，非通用存档（进行中 run 不持久化）。
# （autoload 脚本不声明 class_name：注册名 MetaProgress 即全局单例访问）
extends Node

var unlocked_crew_ids: Array[String] = []   # 已解锁的 unlockable 船员 id（持久）
var _save_path: String = "user://meta.json" # 存盘路径（测试可注入临时路径）

func _ready() -> void:
	load_progress()

# 固定解锁顺序：全部 unlockable crew id 字典序升序（确定性，不依赖扫描顺序）。
func get_unlock_order() -> Array[String]:
	var ids: Array[String] = []
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "unlockable":
			ids.append((def as CrewDefinition).id)
	ids.sort()
	return ids

# 解锁顺序中第一个未解锁者：append + 存盘 + 返回其 id；全已解锁返 ""（无副作用、不写盘）。
func unlock_next() -> String:
	for crew_id in get_unlock_order():
		if not unlocked_crew_ids.has(crew_id):
			unlocked_crew_ids.append(crew_id)
			save_progress()
			return crew_id
	return ""

func is_unlocked(crew_id: String) -> bool:
	return unlocked_crew_ids.has(crew_id)

func to_dict() -> Dictionary:
	return {"unlocked_crew_ids": unlocked_crew_ids.duplicate()}

func from_dict(d: Dictionary) -> void:
	unlocked_crew_ids.clear()
	var arr: Array = d.get("unlocked_crew_ids", [])
	for v in arr:
		unlocked_crew_ids.append(str(v))

func save_progress() -> void:
	var f := FileAccess.open(_save_path, FileAccess.WRITE)
	if f == null:
		push_error("MetaProgress.save_progress: 无法写入 %s" % _save_path)
		return
	f.store_string(JSON.stringify(to_dict()))
	f.close()

func load_progress() -> void:
	if not FileAccess.file_exists(_save_path):
		unlocked_crew_ids.clear()
		return
	var f := FileAccess.open(_save_path, FileAccess.READ)
	if f == null:
		push_error("MetaProgress.load_progress: 无法读取 %s" % _save_path)
		unlocked_crew_ids.clear()
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		from_dict(parsed as Dictionary)
	else:
		push_error("MetaProgress.load_progress: 解析失败，置空")
		unlocked_crew_ids.clear()
