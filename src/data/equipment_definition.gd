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

# ── 稀有度展示（配色/标签，UI 共用单一真实来源）──
const RARITY_LABELS: Array = ["普通", "稀有", "史诗", "稀世", "传奇"]
const RARITY_COLORS: Array = [
	Color("c8c8c8"),  # 普通=灰白
	Color("4a90d9"),  # 稀有=蓝
	Color("9b59b6"),  # 史诗=紫
	Color("e67e22"),  # 稀世=橙
	Color("e74c3c"),  # 传奇=红
]

static func rarity_label(rarity: int) -> String:
	return RARITY_LABELS[clampi(rarity, 0, 4)]

static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity, 0, 4)]
