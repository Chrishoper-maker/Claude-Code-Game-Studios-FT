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
const ISLAND_COUNT_MAX := 5
const DEPLOY_LIMIT := 4

# ── 状态机（ADR-0004）──
enum RunPhase {
	RUN_IDLE,
	RUN_DEPLOYING,
	RUN_ISLAND_BATTLE,
	RUN_RECRUITING,
	RUN_END
}
# ADR-0002 注册契约：current_phase 对外是只读 String。本字典是映射的单一真实来源。
const _PHASE_TO_STRING: Dictionary = {
	RunPhase.RUN_IDLE:          "IDLE",
	RunPhase.RUN_DEPLOYING:     "DEPLOYING",
	RunPhase.RUN_ISLAND_BATTLE: "BATTLE",
	RunPhase.RUN_RECRUITING:    "RECRUITING",
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
var _downed_this_run: Array[int] = []     # 本 run 永久阵亡的运行时 id（R1 公式须排除）

var pending_deploy: Array[CrewDefinition] = []   # 本场出场名单（confirm_deploy 写，BattleScene 读）
var last_run_won: bool = false                   # run-end 页据此判「出航成功/全员阵亡」
var _excluded_offers: Array[String] = []         # 本 run 落选 unit_id（不再 offer）
var _last_offers: Array[String] = []             # 本批候选 unit_id（confirm_recruit 据此排除其余）
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()  # 招募抽样（测试可 seed；断言不变量）

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
		RunPhase.RUN_END:
			EventBus.run_phase_changed.emit("RUN_END")
		RunPhase.RUN_IDLE:
			pass  # IDLE 无需广播（无活跃 run 阶段）

# ── Run 生命周期（route-recruitment-system）──

# 起航：起始编制加入 roster，进入首岛部署。
func start_run() -> void:
	roster.clear()
	_excluded_offers.clear()
	_last_offers.clear()
	pending_deploy.clear()
	_downed_this_run.clear()
	current_island_index = -1
	last_run_won = false
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "starting":
			roster.append(def as CrewDefinition)
	_set_run_phase(RunPhase.RUN_DEPLOYING)

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
			if crew.recruit_pool_tier == "pool" \
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

# 选中候选加入 roster；本批其余候选进 _excluded_offers（本 run 不再 offer）；→DEPLOYING。
func confirm_recruit(unit_id: String) -> void:
	var def := UnitDataManager.get_unit(unit_id)
	if def is CrewDefinition:
		roster.append(def as CrewDefinition)
	else:
		push_error("RunManager.confirm_recruit: unit_id 非 CrewDefinition 或不存在 — %s" % unit_id)
	for offered_id in _last_offers:
		if offered_id != unit_id and not _excluded_offers.has(offered_id):
			_excluded_offers.append(offered_id)
	_last_offers.clear()
	_set_run_phase(RunPhase.RUN_DEPLOYING)

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

func _on_crew_member_downed(unit_id: int) -> void:
	if not _downed_this_run.has(unit_id):
		_downed_this_run.append(unit_id)         # 永久死亡，R1 公式须排除（不跨 run 持久化）
