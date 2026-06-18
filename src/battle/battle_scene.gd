# BattleScene 根编排器（Node3D，ADR-0002）。
# 子系统作为子节点（_ready 自底向上，先于本 _ready 完成订阅）；本脚本只做战斗引导。
# 跨场景状态经 autoload 读取（ADR-0002：不可用 export 预设跨场景引用）。
class_name BattleScene
extends Node3D

@onready var _battle_map: BattleMap = $BattleMap
@onready var _turn_manager: TurnManager = $TurnManager

func _ready() -> void:
	# architecture.md 4d：子系统 _ready 已订阅完毕，此时引导战斗。
	_battle_map.load_map(RunManager.current_island_index)   # 读 autoload 持久状态
	_turn_manager.start_battle()                            # → EventBus.battle_started
