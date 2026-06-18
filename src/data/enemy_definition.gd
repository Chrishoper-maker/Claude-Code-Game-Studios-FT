# 敌人定义（继承 UnitDefinition，ADR-0003）。
class_name EnemyDefinition
extends UnitDefinition

@export_enum("MELEE", "RANGED", "GUARDIAN", "SWARMER") var behavior_type: String
@export var home_pos: Vector2i     # GUARDIAN 守位锚点（enemy-ai-intent）
@export var threat_tier: int
