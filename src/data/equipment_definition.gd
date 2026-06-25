# 装备定义模板（只读静态数据）。纯数值增量 + 稀有度/槽位/套装归属。
# 运行时不写回；由 EquipmentDataManager 扫描缓存。
class_name EquipmentDefinition
extends Resource

enum Rarity { COMMON, RARE, EPIC, ANCIENT, LEGENDARY }   # 0..4（白/蓝/紫/橙/红）
enum Slot { MAIN_WEAPON, OFF_WEAPON, HEAD, ARMOR, GLOVES, LEGS, BOOTS, RING, NECKLACE }  # 0..8

@export var id: String
@export var display_name: String
@export var hp_bonus: int
@export var damage_bonus: int
@export var range_bonus: int
@export var move_bonus: int
@export var rarity: int = Rarity.COMMON   # Rarity 枚举值
@export var slot: int = Slot.MAIN_WEAPON   # Slot 枚举值
@export var set_id: String = ""            # 套装归属（②a 留空，②b 填充）
