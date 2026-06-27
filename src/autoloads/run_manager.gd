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
const INITIAL_GRANT := 3        # 起始/招募直发件数
const SAME_SET_CHANCE := 80     # 3 件同套概率（%，0-99 判定）
const SET_TIERS: Array = [3, 6, 9]   # 套装激活档位阈值（②b-1）
const BATTLE_ROLL := 8          # 战后滚装备候选件数
const BATTLE_PICK := 2          # 玩家从候选中选取件数
const BIAS_CHANCE := 80         # 偏向主套概率（%，0-99 判定）

# ── 状态机（ADR-0004）──
enum RunPhase {
	RUN_IDLE,
	RUN_DEPLOYING,
	RUN_ISLAND_BATTLE,
	RUN_RECRUITING,
	RUN_EQUIPPING,
	RUN_CHARTING,
	RUN_END
}
# ADR-0002 注册契约：current_phase 对外是只读 String。本字典是映射的单一真实来源。
const _PHASE_TO_STRING: Dictionary = {
	RunPhase.RUN_IDLE:          "IDLE",
	RunPhase.RUN_DEPLOYING:     "DEPLOYING",
	RunPhase.RUN_ISLAND_BATTLE: "BATTLE",
	RunPhase.RUN_RECRUITING:    "RECRUITING",
	RunPhase.RUN_EQUIPPING:     "EQUIPPING",
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
var _roster_equipment: Dictionary = {}   # crew_id → { slot:int → equipment_id }（已招船员持有的装备）
var _pending_battle_equip: Dictionary = {}   # crew_id → Array[String]（战后 8 件候选）
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()  # 直发抽样（测试可 seed；断言不变量）
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
		RunPhase.RUN_EQUIPPING:
			EventBus.run_phase_changed.emit("EQUIPPING")
		RunPhase.RUN_CHARTING:
			EventBus.run_phase_changed.emit("CHARTING")
		RunPhase.RUN_END:
			EventBus.run_phase_changed.emit("RUN_END")
		RunPhase.RUN_IDLE:
			pass  # IDLE 无需广播（无活跃 run 阶段）
	# 航点自动存档（run-save #13）：航点存、终局删；BATTLE/IDLE 不动。
	if _autosave_enabled:
		match phase:
			RunPhase.RUN_DEPLOYING, RunPhase.RUN_RECRUITING, RunPhase.RUN_CHARTING, RunPhase.RUN_EQUIPPING:
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
	# 起始船员直发 3 件装备（80% 同套）
	for c in roster:
		_grant_equipment(c.id, roll_initial_equipment())
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
	return offers

# 全部 set_id（去重排序，确定性）。
func _all_set_ids() -> Array[String]:
	var seen: Dictionary = {}
	for eq in EquipmentDataManager.get_all_equipment():
		if eq.set_id != "":
			seen[eq.set_id] = true
	var out: Array[String] = []
	for k in seen:
		out.append(str(k))
	out.sort()
	return out

# 从 pool 里挑不同槽装备追加到 result（就地改 result/used_slots），直到 want 件或耗尽。
func _fill_distinct_slots(result: Array[String], used_slots: Dictionary, pool: Array[EquipmentDefinition], want: int) -> void:
	var candidates: Array = pool.duplicate()
	# 洗牌（Fisher-Yates，走 _rng）。
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	for eq in candidates:
		if result.size() >= want:
			break
		if not used_slots.has(eq.slot):
			used_slots[eq.slot] = true
			result.append(eq.id)

# 起始/招募直发 3 件：80% 概率 3 件同套，否则混搭；均不同槽。
func roll_initial_equipment() -> Array[String]:
	var result: Array[String] = []
	var used_slots: Dictionary = {}
	var all := EquipmentDataManager.get_all_equipment()
	if all.is_empty():
		return result
	if _rng.randi_range(0, 99) < SAME_SET_CHANCE:
		var set_ids := _all_set_ids()
		if not set_ids.is_empty():
			var anchor := set_ids[_rng.randi_range(0, set_ids.size() - 1)]
			var pool: Array[EquipmentDefinition] = []
			for eq in all:
				if eq.set_id == anchor:
					pool.append(eq)
			_fill_distinct_slots(result, used_slots, pool, INITIAL_GRANT)
	# 不足（含混搭分支与同套槽不够）→ 从全池补足。
	_fill_distinct_slots(result, used_slots, all, INITIAL_GRANT)
	return result

# 把若干 eid 按其 slot 写入某船员装备账本（覆盖同槽）。
func _grant_equipment(crew_id: String, eids: Array) -> void:
	var slots: Dictionary = _roster_equipment.get(crew_id, {})
	slots = slots.duplicate()
	for raw in eids:
		var def := EquipmentDataManager.get_equipment(str(raw))
		if def != null:
			slots[def.slot] = str(raw)
	if not slots.is_empty():
		_roster_equipment[crew_id] = slots

# 某船员已占槽集合。
func _owned_slots(crew_id: String) -> Dictionary:
	var out: Dictionary = {}
	var slots: Variant = _roster_equipment.get(crew_id, {})
	if slots is Dictionary:
		for s in (slots as Dictionary):
			out[int(s)] = true
	return out

## 战后滚 8 件：每件独立 80% 偏向主套（优先未拥有空槽件），否则随机。
func roll_battle_equipment(crew_id: String) -> Array[String]:
	var out: Array[String] = []
	var all := EquipmentDataManager.get_all_equipment()
	if all.is_empty():
		return out
	var dominant := get_dominant_set(crew_id)
	var owned := _owned_slots(crew_id)
	var dom_pool: Array = []
	var dom_empty: Array = []
	if dominant != "":
		for eq in all:
			if eq.set_id == dominant:
				dom_pool.append(eq)
				if not owned.has(eq.slot):
					dom_empty.append(eq)
	for i in range(BATTLE_ROLL):
		var pick: EquipmentDefinition = null
		if dominant != "" and _rng.randi_range(0, 99) < BIAS_CHANCE:
			var src: Array = dom_empty if not dom_empty.is_empty() else dom_pool
			if not src.is_empty():
				pick = src[_rng.randi_range(0, src.size() - 1)]
		if pick == null:
			pick = all[_rng.randi_range(0, all.size() - 1)]
		out.append(pick.id)
	return out

## 装上一件：空槽直接装；已占槽需 replace=true 才覆盖（丢弃旧件）。返回是否装上。
func equip_piece(crew_id: String, eid: String, replace: bool) -> bool:
	var def := EquipmentDataManager.get_equipment(eid)
	if def == null:
		return false
	var slots: Dictionary = (_roster_equipment.get(crew_id, {}) as Dictionary).duplicate()
	if slots.has(def.slot) and not replace:
		return false
	slots[def.slot] = eid
	_roster_equipment[crew_id] = slots
	return true

## 某船员补装完成 → 出队列；空则转招募。
func finish_crew_equip(crew_id: String) -> void:
	_pending_battle_equip.erase(crew_id)
	if _pending_battle_equip.is_empty():
		_set_run_phase(RunPhase.RUN_RECRUITING)

## 待补装船员 id → 候选 eid 列表（副本）。
func get_pending_battle_equip() -> Dictionary:
	return _pending_battle_equip.duplicate(true)

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

# 选中候选加入 roster + 直发 3 件装备（80% 同套）。→CHARTING。
func confirm_recruit(unit_id: String) -> void:
	var def := UnitDataManager.get_unit(unit_id)
	if def is CrewDefinition:
		roster.append(def as CrewDefinition)
		_grant_equipment(unit_id, roll_initial_equipment())
	else:
		push_error("RunManager.confirm_recruit: unit_id 非 CrewDefinition 或不存在 — %s" % unit_id)
	for offered_id in _last_offers:
		if offered_id != unit_id and not _excluded_offers.has(offered_id):
			_excluded_offers.append(offered_id)
	_last_offers.clear()
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
	# 非末岛：为本场出战且存活（仍在 roster）的船员滚战后候选。
	_pending_battle_equip.clear()
	var roster_ids: Dictionary = {}
	for c in roster:
		roster_ids[c.id] = true
	for c in pending_deploy:
		if roster_ids.has(c.id):
			_pending_battle_equip[c.id] = roll_battle_equipment(c.id)
	if not _pending_battle_equip.is_empty():
		_set_run_phase(RunPhase.RUN_EQUIPPING)
		_goto_route.call()
		return
	_set_run_phase(RunPhase.RUN_RECRUITING)
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

# 已招船员 crew_id 持有的装备（部署/战斗用）；返回 {slot:int → EquipmentDefinition}，无则空 {}。
func get_equipment_for(crew_id: String) -> Dictionary:
	var out: Dictionary = {}
	var slots: Variant = _roster_equipment.get(crew_id, {})
	if slots is Dictionary:
		for s in (slots as Dictionary):
			var eid := str((slots as Dictionary)[s])
			var def := EquipmentDataManager.get_equipment(eid)
			if def != null:
				out[int(s)] = def
	return out

# ── 套装计数器（②b-1；本期只读，供偏向逻辑/纸娃娃/未来效果引擎共用）──

# 某船员各套持有件数 {set_id → count}（仅含 ≥1；无套装件不计）。
func get_set_counts(crew_id: String) -> Dictionary:
	var counts: Dictionary = {}
	var slots: Variant = _roster_equipment.get(crew_id, {})
	if slots is Dictionary:
		for s in (slots as Dictionary):
			var def := EquipmentDataManager.get_equipment(str((slots as Dictionary)[s]))
			if def != null and def.set_id != "":
				counts[def.set_id] = int(counts.get(def.set_id, 0)) + 1
	return counts

# 主套：持有件数最多的 set_id；并列取字典序最小；无装备返回 ""。
func get_dominant_set(crew_id: String) -> String:
	var counts := get_set_counts(crew_id)
	var best := ""
	var best_n := 0
	for sid in counts:
		var n := int(counts[sid])
		if n > best_n or (n == best_n and (best == "" or str(sid) < best)):
			best = str(sid)
			best_n = n
	return best

# 该套已激活档位（≤件数的最大阈值 ∈ {0,3,6,9}）。
func get_active_set_tier(crew_id: String, set_id: String) -> int:
	var n := int(get_set_counts(crew_id).get(set_id, 0))
	for t in [9, 6, 3]:
		if n >= t:
			return t
	return 0

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
		"roster_equipment": _roster_equipment.duplicate(true),
		"chosen_map_id": _chosen_map_id,
		"visited_map_ids": _visited_map_ids.duplicate(),
		"last_route_offers": _last_route_offers.duplicate(),
		"pending_battle_equip": _pending_battle_equip.duplicate(true),
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
	# 装备账本恢复：仅保留 crew 仍在 roster 的条目（缺失定义优雅跳过）。
	# 支持新嵌套格式 {slot:int → eid} 与旧扁平格式 {crew_id → eid}（旧档迁移）。
	_roster_equipment.clear()
	var roster_id_set: Dictionary = {}
	for c in roster:
		roster_id_set[c.id] = true
	var re: Variant = d.get("roster_equipment", {})
	if re is Dictionary:
		for k in (re as Dictionary):
			var cid := str(k)
			if not roster_id_set.has(cid):
				continue
			var val: Variant = (re as Dictionary)[k]
			var slots: Dictionary = {}
			if val is Dictionary:
				for s in (val as Dictionary):
					var eid := str((val as Dictionary)[s])
					if EquipmentDataManager.get_equipment(eid) != null:
						slots[int(s)] = eid
			else:
				# 旧档迁移：单 eid → 按其 slot 放入
				var eid := str(val)
				var edef := EquipmentDataManager.get_equipment(eid)
				if edef != null:
					slots[edef.slot] = eid
			if not slots.is_empty():
				_roster_equipment[cid] = slots
	# 战后候选恢复：仅保留仍在 roster 的 crew（§5 spec 要求），且 eid 必须存在。
	_pending_battle_equip.clear()
	var pbe: Variant = d.get("pending_battle_equip", {})
	if pbe is Dictionary:
		for k in (pbe as Dictionary):
			var cid := str(k)
			if not roster_id_set.has(cid):
				continue
			var raw: Variant = (pbe as Dictionary)[k]
			var eids: Array[String] = []
			if raw is Array:
				for e in (raw as Array):
					if EquipmentDataManager.get_equipment(str(e)) != null:
						eids.append(str(e))
			if not eids.is_empty():
				_pending_battle_equip[cid] = eids

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
		"EQUIPPING": return RunPhase.RUN_EQUIPPING
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
