# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: 单位数据 schema 形状（ADR-0003 结构，目录扫描管线本切片降级为代码实例化）
# Date: 2026-06-18
#
# 单位定义模板（只读）。切片中由 unit_factory 代码实例化，不从 .tres 目录扫描（范围切，见 REPORT）。
class_name UnitDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_enum("crew", "enemy") var faction: String
@export_enum("swordsman", "gunner", "bulwark", "medic") var unit_class: String
@export var max_hp: int
@export var move_range: int
@export var attack_range: int        # 切比雪夫(近战=1) / 曼哈顿(炮手≥2)
@export var base_damage: int
@export var bond_tags: Array[String] = []
