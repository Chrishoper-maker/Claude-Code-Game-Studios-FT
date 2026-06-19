# BattleScene 根编排器（Node3D，ADR-0002）。
# 子系统作为子节点（_ready 自底向上，先于本 _ready 完成订阅）；本脚本只做战斗引导。
# 跨场景状态经 autoload 读取（ADR-0002：不可用 export 预设跨场景引用）。
class_name BattleScene
extends Node3D

@onready var _grid_board: GridBoard = $GridBoard
@onready var _turn_manager: TurnManager = $TurnManager
@onready var _battle_resolution: BattleResolution = $BattleResolution
@onready var _adjacency_bond: AdjacencyBond = $AdjacencyBond
@onready var _enemy_ai: EnemyAI = $EnemyAI
@onready var _battle_map: BattleMap = $BattleMap

func _ready() -> void:
	# 依赖注入（DI over singleton）：按依赖关系接线兄弟系统，再引导战斗。
	_battle_resolution.setup(_grid_board, _turn_manager)
	_adjacency_bond.setup(_grid_board, _turn_manager, _battle_resolution)
	_enemy_ai.setup(_grid_board, _turn_manager, _battle_resolution)
	_battle_map.setup(_grid_board, _turn_manager)
	# architecture.md 4d：引导战斗。
	_battle_map.load_map(RunManager.current_island_index)   # 读 autoload 持久状态 → 部署
	_turn_manager.start_battle()                            # → EventBus.battle_started
