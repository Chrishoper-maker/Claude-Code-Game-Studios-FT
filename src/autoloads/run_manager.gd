# Run 状态机（autoload #4，ADR-0004 + ADR-0002 + route-recruitment-system）。
# 跨场景持久：roster / current_island_index / _downed_this_run 不存在于任何 Scene 节点内。
# run_phase_changed 的唯一发射方（GDD 契约）。
#
# foundation 范围：状态机 + String 门面 + 场景切换钩子已落地；招募/部署的具体规则
# （三选一无放回随机、同职业排除、offer 生成）留 TODO，由 route-recruitment 实现 epic 完成。
# （autoload 脚本不声明 class_name：注册名 RunManager 即全局单例访问）
extends Node

# ── 注册常量（entities.yaml）──
const STARTING_CREW := 2
const RECRUIT_OFFER_COUNT := 3
const ROUTE_OFFER_COUNT := 3
const ISLAND_COUNT_MAX := 5
const DEPLOY_LIMIT := 4

# ── 状态机（ADR-0004）──
enum RunPhase {
	RUN_IDLE,
	RUN_DEPLOYING,
	RUN_ISLAND_BATTLE,
	RUN_RECRUITING,
	RUN_CHARTING,
	RUN_END
}
# ADR-0002 注册契约：current_phase 对外是只读 String。本字典是映射的单一真实来源。
const _PHASE_TO_STRING: Dictionary = {
	RunPhase.RUN_IDLE:          "IDLE",
	RunPhase.RUN_DEPLOYING:     "DEPLOYING",
	RunPhase.RUN_ISLAND_BATTLE: "BATTLE",
	RunPhase.RUN_RECRUITING:    "RECRUITING",
	RunPhase.RUN_CHARTING:      "CHARTING",
	RunPhase.RUN_END:           "RUN_END",
}

var _phase: RunPhase = RunPhase.RUN_IDLE

# ADR-0002 注册契约：只读 String 门面
var current_phase: String:
	get:
		return _PHASE_TO_STRING[_phase]

# 独立非状态变量（ADR-0002/0004）。约定只读，仅本类内部 confirm_deploy 推进。
var current_island_index: int = -1
var roster: Array[CrewDefinition] = []
var _downed_this_run: Array[String] = []  # 本 run 永久阵亡的持久 crew id（roster 移除 + 招募排除）
var _downed_pending_notice: Array[String] = []  # 本场待展示阵亡通知的 crew id（RouteScene 弹卡后清空）

var pending_deploy: Array[CrewDefinition] = []   # 本场出场名单（confirm_deploy 写，BattleScene 读）
var last_run_won: bool = false                   # run-end 页据此判「出航成功/全员阵亡」
var _unlocked_this_run: String = ""               # 本航新解锁的悬赏船员持久 id（run-end 展示；空=无）
var _excluded_offers: Array[String] = []         # 本 run 落选 unit_id（不再 offer）
var _last_offers: Array[String] = []             # 本批候选 unit_id（confirm_recruit 据此排除其余）
var _chosen_map_id: String = ""             # 本次选航选定的 map_id（battle_map.load_map 读）
var _visited_map_ids: Array[String] = []     # 本 run 已访问 map_id（选航不重复）
var _last_route_offers: Array[String] = []   # 本批选航候选 map_id（confirm_route 据此校验）
var _roster_equipment: Dictionary = {}   # crew_id → equipment_id（已招船员持有的装备）
var _offer_equipment: Dictionary = {}    # crew_id → equipment_id（本批候选滚到的装备）
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()  # 招募抽样（测试可 seed；断言不变量）
var _save_path: String = "user://run.json"        # 进行中 run 存档路径（测试可注入）
var _autosave_enabled: bool = true                 # 航点自动存档开关（Task 2 钩子读取；测试关）

# 导航接缝（DI over singleton）：默认转调 SceneManager，单测覆盖为 no-op 以免真的切场景。
var _goto_battle: Callable
var _goto_route: Callable
func _default_goto_battle() -> void: SceneManager.goto_battle()
func _default_goto_route() -> void: SceneManager.goto_route()

func _ready() -> void:
	# 映射完整性守卫：新增 RunPhase 而漏更新 _PHASE_TO_STRING 时立即触发
	assert(_PHASE_TO_STRING.size() == RunPhase.size(),
		"RunManager: _PHASE_TO_STRING 不完整 — 新增 RunPhase 后须同步更新")
	_goto_battle = _default_goto_battle
	_goto_route = _default_goto_route
	EventBus.battle_won.connect(_on_battle_won)
	EventBus.battle_lost.connect(_on_battle_lost)
	EventBus.crew_member_downed.connect(_on_crew_member_downed)

# ── 状态转换（ADR-0004：唯一转换入口 + 进入时发信号）──
func _set_run_phase(new_phase: RunPhase) -> void:
	_phase = new_phase
	_on_run_phase_entered(new_phase)

func _on_run_phase_entered(phase: RunPhase) -> void:
	match phase:
		RunPhase.RUN_DEPLOYING:
			EventBus.run_phase_changed.emit("DEPLOYING")
		RunPhase.RUN_ISLAND_BATTLE:
			EventBus.run_phase_changed.emit("BATTLE")
		RunPhase.RUN_RECRUITING:
			EventBus.run_phase_changed.emit("RECRUITING")
		RunPhase.RUN_CHARTING:
			EventBus.run_phase_changed.emit("CHARTING")
		RunPhase.RUN_END:
			EventBus.run_phase_changed.emit("RUN_END")
		RunPhase.RUN_IDLE:
			pass  # IDLE 无需广播（无活跃 run 阶段）
	# 航点自动存档（run-save #13）：航点存、终局删；BATTLE/IDLE 不动。
	if _autosave_enabled:
		match phase:
			RunPhase.RUN_DEPLOYING, RunPhase.RUN_RECRUITING, RunPhase.RUN_CHARTING:
				save_run()
			RunPhase.RUN_END:
				delete_save()

# ── Run 生命周期（route-recruitment-system）──

# 起航：起始编制加入 roster，进入首岛部署。
func start_run() -> void:
	roster.clear()
	_excluded_offers.clear()
	_last_offers.clear()
	_roster_equipment.clear()
	_offer_equipment.clear()
	pending_deploy.clear()
	_downed_this_run.clear()
	_downed_pending_notice.clear()
	_chosen_map_id = ""
	_visited_map_ids.clear()
	_last_route_offers.clear()
	current_island_index = -1
	last_run_won = false
	_unlocked_this_run = ""
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "starting":
			roster.append(def as CrewDefinition)
	_set_run_phase(RunPhase.RUN_CHARTING)

func get_roster() -> Array[CrewDefinition]:
	return roster

# 三选一招募候选（GDD Rule 1-2 / R1）：无放回随机 ≤3 名，且三者 unit_class 互不相同
# （某职业可用不足时豁免）。排除 roster 内与 _excluded_offers 内 unit_id。写入 _last_offers。
func get_recruit_offers() -> Array[CrewDefinition]:
	var roster_ids: Dictionary = {}
	for c in roster:
		roster_ids[c.id] = true
	var pool: Array[CrewDefinition] = []
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition:
			var crew := def as CrewDefinition
			if (crew.recruit_pool_tier == "pool" \
					or (crew.recruit_pool_tier == "unlockable" and MetaProgress.is_unlocked(crew.id))) \
					and not roster_ids.has(crew.id) \
					and not _excluded_offers.has(crew.id):
				pool.append(crew)
	# Fisher-Yates 用持有的 _rng（确定性，测试可 seed）。
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	# 取前 ≤3 名，职业互不相同。
	var offers: Array[CrewDefinition] = []
	var seen_classes: Dictionary = {}
	for crew in pool:
		if offers.size() >= RECRUIT_OFFER_COUNT:
			break
		if seen_classes.has(crew.unit_class):
			continue
		seen_classes[crew.unit_class] = true
		offers.append(crew)
	_last_offers.clear()
	for o in offers:
		_last_offers.append(o.id)
	# 为每名候选随机滚一件装备（有放回；池空则不滚）。_rng 顺序确定 → 存档可复现。
	_offer_equipment.clear()
	var equip_pool := EquipmentDataManager.get_all_equipment()
	if not equip_pool.is_empty():
		for crew in offers:
			var pick := equip_pool[_rng.randi_range(0, equip_pool.size() - 1)]
			_offer_equipment[crew.id] = pick.id
	return offers

# 即将抵达岛号 → 目标 island_tier 集合（可调）。next_idx = current_island_index + 1。
func _target_tiers_for_island(next_idx: int) -> Array[int]:
	match next_idx:
		0: return [1]
		1, 2: return [1, 2]
		3: return [2, 3]
		_: return [3]   # 4 及之后（末岛）

# 三张选航候选：按"即将抵达岛"的目标 tier 抽 ≤ROUTE_OFFER_COUNT 张未访问地图；
# 不足则放宽 tier（全体未访问），再不足则放宽 visited（全体）。确定性（_rng + map_id 排序）。
func get_route_offers() -> Array[MapDefinition]:
	var next_idx := current_island_index + 1
	var tiers := _target_tiers_for_island(next_idx)
	var pool: Array[MapDefinition] = []
	# 主池：目标 tier 未访问
	for t in tiers:
		for m in MapDataManager.get_maps_for_tier(t):
			if not _visited_map_ids.has(m.map_id) and not pool.has(m):
				pool.append(m)
	# 降级①：放宽到全体未访问
	if pool.size() < ROUTE_OFFER_COUNT:
		for m in MapDataManager.get_all_maps():
			if not _visited_map_ids.has(m.map_id) and not pool.has(m):
				pool.append(m)
	# 降级②：仍不足则放宽 visited（允许历史重复，但本批仍去重）
	if pool.size() < ROUTE_OFFER_COUNT:
		for m in MapDataManager.get_all_maps():
			if not pool.has(m):
				pool.append(m)
	# 先按 map_id 排序消除扫描顺序差异 → 再 Fisher-Yates（确定性）
	pool.sort_custom(func(a: MapDefinition, b: MapDefinition) -> bool: return a.map_id < b.map_id)
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var offers: Array[MapDefinition] = []
	for m in pool:
		if offers.size() >= ROUTE_OFFER_COUNT:
			break
		offers.append(m)
	_last_route_offers.clear()
	for o in offers:
		_last_route_offers.append(o.map_id)
	return offers

# 选定航点：记 map_id + 标记本 run 已访问 + 清候选 → DEPLOYING。
# 坏 id（无定义或不在本批候选）：push_error 且不改状态（仿 confirm_recruit）。
func confirm_route(map_id: String) -> void:
	if MapDataManager.get_map(map_id) == null:
		push_error("RunManager.confirm_route: 未知 map_id — %s" % map_id)
		return
	if not _last_route_offers.has(map_id):
		push_error("RunManager.confirm_route: map_id 不在本批候选 — %s" % map_id)
		return
	_chosen_map_id = map_id
	if not _visited_map_ids.has(map_id):
		_visited_map_ids.append(map_id)
	_last_route_offers.clear()
	_set_run_phase(RunPhase.RUN_DEPLOYING)

# 本次选航选定的 map_id（battle_map.load_map 读）；未选则 ""。
func get_chosen_map_id() -> String:
	return _chosen_map_id

# 选中候选加入 roster；本批其余候选进 _excluded_offers（本 run 不再 offer）；→DEPLOYING。
func confirm_recruit(unit_id: String) -> void:
	var def := UnitDataManager.get_unit(unit_id)
	if def is CrewDefinition:
		roster.append(def as CrewDefinition)
		var picked_eid := str(_offer_equipment.get(unit_id, ""))
		if picked_eid != "":
			_roster_equipment[unit_id] = picked_eid
	else:
		push_error("RunManager.confirm_recruit: unit_id 非 CrewDefinition 或不存在 — %s" % unit_id)
	for offered_id in _last_offers:
		if offered_id != unit_id and not _excluded_offers.has(offered_id):
			_excluded_offers.append(offered_id)
	_last_offers.clear()
	_offer_equipment.clear()
	_set_run_phase(RunPhase.RUN_CHARTING)

# 部署确认 → 进入战斗（ADR-0002 场景切换序列）。pending_deploy = roster 中被选 id 的 defs。
func confirm_deploy(selected_ids: Array) -> void:
	pending_deploy.clear()
	for c in roster:
		if selected_ids.has(c.id):
			pending_deploy.append(c)
	current_island_index += 1
	_set_run_phase(RunPhase.RUN_ISLAND_BATTLE)   # 发 run_phase_changed("BATTLE")
	_goto_battle.call()

func get_pending_deploy() -> Array[CrewDefinition]:
	return pending_deploy

# 战斗胜利 → 招募（或终局）。ADR-0002：RunManager 是发射方，再调 SceneManager。
func _on_battle_won() -> void:
	if current_island_index + 1 >= ISLAND_COUNT_MAX:
		last_run_won = true
		_set_run_phase(RunPhase.RUN_END)
		EventBus.run_completed.emit(true, current_island_index + 1, roster.duplicate())
		_unlocked_this_run = MetaProgress.unlock_next()   # 悬赏成长：通关解锁下一名 unlockable（含存盘）；记录供 run-end 展示
		_goto_route.call()
		return
	_set_run_phase(RunPhase.RUN_RECRUITING)      # 发 run_phase_changed("RECRUITING")
	_goto_route.call()

# 战斗失败 → run 终局（全员阵亡）。切回 RouteScene 显示 run-end。
func _on_battle_lost() -> void:
	last_run_won = false
	_set_run_phase(RunPhase.RUN_END)
	EventBus.run_completed.emit(false, current_island_index + 1, roster.duplicate())
	_goto_route.call()

# 我方永久死亡：移出 roster（本 run 不再部署）+ 记录 + 排除招募（不复活）。crew_id = 持久身份。
func _on_crew_member_downed(crew_id: String) -> void:
	if _downed_this_run.has(crew_id):
		return
	_downed_this_run.append(crew_id)
	_downed_pending_notice.append(crew_id)
	for i in range(roster.size() - 1, -1, -1):
		if roster[i].id == crew_id:
			roster.remove_at(i)
	if not _excluded_offers.has(crew_id):
		_excluded_offers.append(crew_id)
	_roster_equipment.erase(crew_id)

# 阵亡通知卡数据接口（route-recruitment-ui）：本场待通知 crew id 副本。
func get_pending_downed_notice() -> Array[String]:
	return _downed_pending_notice.duplicate()

func clear_downed_notice() -> void:
	_downed_pending_notice.clear()

# 本 run 累计阵亡的持久 crew id 副本（run-end 总结/未来存档）。
func get_downed_this_run() -> Array[String]:
	return _downed_this_run.duplicate()

# 本航新解锁的悬赏船员持久 id（run-end 展示用）；无则 ""。
func get_unlocked_this_run() -> String:
	return _unlocked_this_run

# 本批候选 crew_id 滚到的装备（招募卡 UI 用）；无则 null。
func get_offer_equipment(crew_id: String) -> EquipmentDefinition:
	var eid := str(_offer_equipment.get(crew_id, ""))
	if eid == "":
		return null
	return EquipmentDataManager.get_equipment(eid)

# 已招船员 crew_id 持有的装备（部署/战斗用）；无则 null。
func get_equipment_for(crew_id: String) -> EquipmentDefinition:
	var eid := str(_roster_equipment.get(crew_id, ""))
	if eid == "":
		return null
	return EquipmentDataManager.get_equipment(eid)

# ── 存档（run-save #13）──

# 序列化进行中 run 状态（纯，无 I/O）。crew 存 id，rng 存 str 防精度丢失。
func to_save_dict() -> Dictionary:
	var roster_ids: Array[String] = []
	for c in roster:
		roster_ids.append(c.id)
	var pending_ids: Array[String] = []
	for c in pending_deploy:
		pending_ids.append(c.id)
	return {
		"version": 1,
		"phase": current_phase,
		"island_index": current_island_index,
		"last_run_won": last_run_won,
		"roster": roster_ids,
		"pending_deploy": pending_ids,
		"downed_this_run": _downed_this_run.duplicate(),
		"downed_pending_notice": _downed_pending_notice.duplicate(),
		"excluded_offers": _excluded_offers.duplicate(),
		"last_offers": _last_offers.duplicate(),
		"rng_state": str(_rng.state),
		"roster_equipment": _roster_equipment.duplicate(),
		"chosen_map_id": _chosen_map_id,
		"visited_map_ids": _visited_map_ids.duplicate(),
		"last_route_offers": _last_route_offers.duplicate(),
	}

# 反序列化恢复（直接赋 _phase，不发信号）。缺失 crew id 防御性跳过。
func load_from_save_dict(d: Dictionary) -> void:
	current_island_index = int(d.get("island_index", current_island_index))
	last_run_won = bool(d.get("last_run_won", last_run_won))
	roster.clear()
	for rid in (d.get("roster", []) as Array):
		var def := UnitDataManager.get_unit(str(rid))
		if def is CrewDefinition:
			roster.append(def as CrewDefinition)
	pending_deploy.clear()
	for pid in (d.get("pending_deploy", []) as Array):
		var def := UnitDataManager.get_unit(str(pid))
		if def is CrewDefinition:
			pending_deploy.append(def as CrewDefinition)
	_downed_this_run = _to_string_array(d.get("downed_this_run", []))
	_downed_pending_notice = _to_string_array(d.get("downed_pending_notice", []))
	_excluded_offers = _to_string_array(d.get("excluded_offers", []))
	_last_offers = _to_string_array(d.get("last_offers", []))
	_chosen_map_id = str(d.get("chosen_map_id", ""))
	_visited_map_ids = _to_string_array(d.get("visited_map_ids", []))
	_last_route_offers = _to_string_array(d.get("last_route_offers", []))
	_phase = _phase_from_string(str(d.get("phase", "IDLE")))
	_rng.state = int(str(d.get("rng_state", "0")))
	# 装备账本恢复：仅保留 crew 仍在 roster、且 equipment 有定义的条目（缺失优雅跳过）。
	_roster_equipment.clear()
	var roster_id_set: Dictionary = {}
	for c in roster:
		roster_id_set[c.id] = true
	var re: Variant = d.get("roster_equipment", {})
	if re is Dictionary:
		for k in (re as Dictionary):
			var cid := str(k)
			var eid := str((re as Dictionary)[k])
			if roster_id_set.has(cid) and EquipmentDataManager.get_equipment(eid) != null:
				_roster_equipment[cid] = eid

func _to_string_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for e in (v as Array):
			out.append(str(e))
	return out

func _phase_from_string(s: String) -> RunPhase:
	match s:
		"IDLE": return RunPhase.RUN_IDLE
		"DEPLOYING": return RunPhase.RUN_DEPLOYING
		"BATTLE": return RunPhase.RUN_ISLAND_BATTLE
		"RECRUITING": return RunPhase.RUN_RECRUITING
		"CHARTING": return RunPhase.RUN_CHARTING
		"RUN_END": return RunPhase.RUN_END
		_: return RunPhase.RUN_IDLE

func save_run() -> void:
	var f := FileAccess.open(_save_path, FileAccess.WRITE)
	if f == null:
		push_error("RunManager.save_run: 无法写入 %s" % _save_path)
		return
	f.store_string(JSON.stringify(to_save_dict()))
	f.close()

func load_run() -> void:
	if not FileAccess.file_exists(_save_path):
		return
	var f := FileAccess.open(_save_path, FileAccess.READ)
	if f == null:
		push_error("RunManager.load_run: 无法读取 %s" % _save_path)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		load_from_save_dict(parsed as Dictionary)
	else:
		push_error("RunManager.load_run: 解析失败，保留当前状态")

func has_save() -> bool:
	return FileAccess.file_exists(_save_path)

func delete_save() -> void:
	if FileAccess.file_exists(_save_path):
		DirAccess.remove_absolute(_save_path)
