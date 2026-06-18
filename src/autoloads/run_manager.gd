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

func _ready() -> void:
	# 映射完整性守卫：新增 RunPhase 而漏更新 _PHASE_TO_STRING 时立即触发
	assert(_PHASE_TO_STRING.size() == RunPhase.size(),
		"RunManager: _PHASE_TO_STRING 不完整 — 新增 RunPhase 后须同步更新")
	EventBus.battle_won.connect(_on_battle_won)
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
# TODO(route epic)：从 UnitDataManager 取 recruit_pool_tier=="starting" 的 CrewDefinition 填 roster。
func start_run() -> void:
	roster.clear()
	_downed_this_run.clear()
	current_island_index = -1
	_set_run_phase(RunPhase.RUN_DEPLOYING)

func get_roster() -> Array[CrewDefinition]:
	return roster

# 三选一招募候选。TODO(route epic)：无放回随机 + 同职业排除 + 落选者本 run 不再出现。
func get_recruit_offers() -> Array[CrewDefinition]:
	return []

# TODO(route epic)：将选中候选加入 roster，落选者移出本 run 候选池，转 DEPLOYING。
func confirm_recruit(_unit_id: String) -> void:
	_set_run_phase(RunPhase.RUN_DEPLOYING)

# 部署确认 → 进入战斗（ADR-0002 场景切换序列）。
func confirm_deploy(_selected_ids: Array) -> void:
	current_island_index += 1
	_set_run_phase(RunPhase.RUN_ISLAND_BATTLE)   # 发 run_phase_changed("BATTLE")
	SceneManager.goto_battle()

# 战斗胜利 → 招募（或终局）。ADR-0002：RunManager 是发射方，再调 SceneManager。
func _on_battle_won() -> void:
	if current_island_index + 1 >= ISLAND_COUNT_MAX:
		_set_run_phase(RunPhase.RUN_END)
		EventBus.run_completed.emit(true, current_island_index + 1, roster.duplicate())
		return
	_set_run_phase(RunPhase.RUN_RECRUITING)      # 发 run_phase_changed("RECRUITING")
	SceneManager.goto_route()

func _on_crew_member_downed(unit_id: int) -> void:
	if not _downed_this_run.has(unit_id):
		_downed_this_run.append(unit_id)         # 永久死亡，R1 公式须排除（不跨 run 持久化）
