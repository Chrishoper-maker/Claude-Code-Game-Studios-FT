# 敌方编制槽（MapDefinition.enemy_roster 子资源，ADR-0003 / battle-map-system）。
# unit_definition_id 在 MapDataManager 校验期须能在 UnitDataManager 中找到。
class_name EnemySlotDefinition
extends Resource

@export var unit_definition_id: String
@export var grid_position: Vector2i
@export_enum("MELEE", "RANGED", "GUARDIAN", "SWARMER") var behavior_type: String
@export var home_pos: Vector2i
