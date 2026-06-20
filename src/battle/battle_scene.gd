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
# 出场名单由 RunManager.get_pending_deploy() 提供（route confirm_deploy 写入）。

func _ready() -> void:
	# 依赖注入（DI over singleton）：按依赖关系接线兄弟系统，再引导战斗。
	_battle_resolution.setup(_grid_board, _turn_manager)
	_adjacency_bond.setup(_grid_board, _turn_manager, _battle_resolution)
	_enemy_ai.setup(_grid_board, _turn_manager, _battle_resolution)
	_battle_map.setup(_grid_board, _turn_manager)
	_bond_gauge_burst.setup(_grid_board, _turn_manager, _battle_resolution)  # 订阅充能信号
	_player_turn_controller.setup(_turn_manager, _grid_board, _battle_resolution, _bond_gauge_burst, _board_highlighter, _battle_hud)
	_battle_hud.setup(_player_turn_controller, _turn_manager)
	_damage_floater.setup(_unit_renderer, func(id: int) -> String: return _faction_of(id))
	_camera_shake.setup(get_viewport().get_camera_3d())
	# architecture.md 4d：引导战斗。
	_battle_map.load_map(RunManager.current_island_index)   # 读 autoload 持久状态 → 部署敌方
	_deploy_run_crew()                                      # 按 run roster 自动部署玩家方
	_spawn_all_views()                                      # 已部署单位 → 生成视觉节点
	_turn_manager.start_battle()                            # → EventBus.battle_started

# 按 run roster 部署：读 pending_deploy → 取前 N 个，自动排入部署区前 N 个可用格。
# N = min(出场名单数, 可用部署格数)。A 全员自动部署，忽略 DEPLOY_LIMIT（手动选归子项目 B）。
func _deploy_run_crew() -> void:
	var pending := RunManager.get_pending_deploy()
	if pending.is_empty():
		return
	var cells := _battle_map.get_deploy_zone_available()
	var n: int = min(pending.size(), cells.size())
	if n <= 0:
		return
	var defs: Array = []
	var positions: Array = []
	for i in n:
		defs.append(pending[i])
		positions.append(cells[i])
	_battle_map.deploy_crew(defs, positions)

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
