# 地图定义（静态战斗地图资源，ADR-0003 / battle-map-system）。
class_name MapDefinition
extends Resource

@export var map_id: String
@export var display_name: String
@export var terrain_data: Array[TerrainCell]            # 非 EMPTY 格列表
@export var deploy_zone: Array[Vector2i]
@export var enemy_roster: Array[EnemySlotDefinition]
@export var island_tier: int
@export var annotated_engagement_distance: Dictionary   # {min:int, max:int} — 仅设计标注
@export var map_scene_id: String                        # "" = null（MVP 白盒占位）
