# 装备定义模板（只读静态数据）。纯数值增量，作用于携带它的船员 UnitInstance。
# 运行时不写回；与 UnitDefinition 并列，由 EquipmentDataManager 扫描缓存。
class_name EquipmentDefinition
extends Resource

@export var id: String
@export var display_name: String
@export var hp_bonus: int
@export var damage_bonus: int
@export var range_bonus: int
@export var move_bonus: int
