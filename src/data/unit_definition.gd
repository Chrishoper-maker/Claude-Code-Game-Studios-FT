# 单位定义模板（只读静态数据，ADR-0003）。
# 运行时可变状态在独立的 UnitInstance（非 Resource）中，绝不写回本模板。
# 路径稳定区：.tres 文件存储本脚本路径引用，移动/改名会破坏所有关联 .tres。
class_name UnitDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_enum("crew", "enemy") var faction: String
@export_enum("swordsman", "gunner", "bulwark", "medic", "navigator", "musician") var unit_class: String
@export var max_hp: int
@export var move_range: int
@export var attack_range: int
@export var base_damage: int
@export var bond_tags: Array[String]
@export var class_action_id: String  # "" = 无职业动词（等价 null）
