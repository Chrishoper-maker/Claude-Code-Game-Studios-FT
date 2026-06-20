# BattleScene 根编排器（Node3D，ADR-0002）。
# 子系统作为子节点（_ready 自底向上，先于本 _ready 完成订阅）；本脚本只做战斗引导。
# 跨场景状态经 autoload 读取（ADR-0002：不可用 export 预设跨场景引用）。
class_name BattleScene
extends Node3D

@onready var _grid_board: GridBoard = $GridBoard
@onready var _unit_renderer: UnitRenderer = $UnitRenderer
@onready var _turn_manager: TurnManager = $TurnManager
@onready var _battle_resolution: BattleResolution = $BattleResolution
@onready var _adjacency_bond: AdjacencyBond = $AdjacencyBond
@onready var _enemy_ai: EnemyAI = $EnemyAI
@onready var _battle_map: BattleMap = $BattleMap
@onready var _bond_gauge_burst: BondGaugeBurst = $BondGaugeBurst
@onready var _board_highlighter: BoardHighlighter = $BoardHighlighter
@onready var _player_turn_controller: PlayerTurnController = $PlayerTurnController
@onready var _battle_hud: BattleHUD = $HUDLayer/BattleHUD
@onready var _damage_floater: DamageFloater = $HUDLayer/DamageFloater
@onready var _camera_shake: CameraShake = $CameraShake
@onready var _battle_result_overlay: BattleResultOverlay = $BurstLayer/BattleResultOverlay

# TEMP：DeployScreen story 落地前的起始 crew 引导（破阵先锋配对，两格相邻 → 可触发爆发）。
const _BOOTSTRAP_CREW := ["crew_swordsman_01", "crew_bulwark_01"]
const _BOOTSTRAP_CELLS := [Vector2i(3, 7), Vector2i(3, 6)]

func _ready() -> void:
	# 依赖注入（DI over singleton）：按依赖关系接线兄弟系统，再引导战斗。
	_battle_resolution.setup(_grid_board, _turn_manager)
	_adjacency_bond.setup(_grid_board, _turn_manager, _battle_resolution)
	_enemy_ai.setup(_grid_board, _turn_manager, _battle_resolution)
	_battle_map.setup(_grid_board, _turn_manager)
	_bond_gauge_burst.setup(_grid_board, _turn_manager, _battle_resolution)  # 订阅充能信号
	_player_turn_controller.setup(_turn_manager, _grid_board, _battle_resolution, _bond_gauge_burst, _board_highlighter, _battle_hud)
	_battle_hud.setup(_player_turn_controller, _turn_manager)
	# TEMP：航线/招募元层未做 → 断开 RunManager 的胜利跳转（否则 goto_route 因 route_scene 未赋值 assert 崩）。
	if EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.disconnect(RunManager._on_battle_won)
	_damage_floater.setup(_unit_renderer, func(id: int) -> String: return _faction_of(id))
	_camera_shake.setup(get_viewport().get_camera_3d())
	_battle_result_overlay.setup()
	# architecture.md 4d：引导战斗。
	_battle_map.load_map(RunManager.current_island_index)   # 读 autoload 持久状态 → 部署敌方
	_deploy_starting_crew()                                 # TEMP：自动部署玩家方
	_spawn_all_views()                                      # 已部署单位 → 生成视觉节点
	_turn_manager.start_battle()                            # → EventBus.battle_started

# TEMP（待 DeployScreen story 取代）：自动部署起始 crew，否则无友方 → 秒败、画面只剩敌人。
func _deploy_starting_crew() -> void:
	var crew_defs: Array = []
	for crew_id in _BOOTSTRAP_CREW:
		var def := UnitDataManager.get_unit(crew_id)
		if def == null:
			return
		crew_defs.append(def)
	_battle_map.deploy_crew(crew_defs, _BOOTSTRAP_CELLS)

# 为所有已注册单位生成 UnitView（数据→视觉单向，ADR-0007）。
func _spawn_all_views() -> void:
	for battle_id in _turn_manager.get_alive_allies() + _turn_manager.get_alive_enemies():
		var inst := _turn_manager.get_unit(battle_id)
		var view := _unit_renderer.spawn_view(inst.definition.unit_class, inst.definition.faction, battle_id, inst.grid_position)
		_unit_renderer.set_unit_max_hp(battle_id, inst.definition.max_hp)
		view.set_hp(inst.current_hp, inst.definition.max_hp)

# 辅助：根据 battle_id 查询阵营字符串（传给 DamageFloater 的 faction_lookup）。
func _faction_of(battle_id: int) -> String:
	var u := _turn_manager.get_unit(battle_id)
	return u.definition.faction if u != null else "enemy"
