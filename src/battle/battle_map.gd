# 地图加载/校验（architecture.md §136 / battle-map-system）。MAP_* 状态机（ADR-0004）。
# 骨架 stub：状态枚举 + 接口就位，加载/校验/地形初始化实现留 battle-map story。
class_name BattleMap
extends Node

enum MapState {
	MAP_UNLOADED,
	MAP_VALIDATING,
	MAP_LOADING,
	MAP_READY,
	MAP_ACTIVE,
	MAP_RESOLVED,
}

var _map_state: MapState = MapState.MAP_UNLOADED

# 由 BattleScene._ready() 调用（ADR-0002 / architecture.md 4d）。
func load_map(_island_index: int) -> void:
	# TODO(battle-map story)：MapDataManager.get_map → 校验 F1–F6 → 初始化 GridBoard 地形 →
	#   EventBus.map_loaded.emit / map_load_failed.emit；推进 MAP_* 状态机。
	pass

func get_map_state() -> MapState:
	return _map_state

func is_map_ready() -> bool:
	return _map_state == MapState.MAP_READY

func get_deploy_zone_available(_occupied: Array = []) -> Array[Vector2i]:
	return []
