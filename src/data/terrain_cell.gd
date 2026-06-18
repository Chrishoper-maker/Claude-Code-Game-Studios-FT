# 地形格（MapDefinition.terrain_data 子资源，ADR-0003 / battle-map-system）。
# 仅记录非 EMPTY 格（BLOCKED / COVER）；EMPTY 为隐式默认。
class_name TerrainCell
extends Resource

@export var pos: Vector2i
@export_enum("BLOCKED", "COVER") var type: String
