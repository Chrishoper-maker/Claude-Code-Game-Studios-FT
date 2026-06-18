# 具名配对羁绊覆盖（CrewDefinition 子资源，ADR-0003）。
# foundation 占位：完整字段由 unit-data-system / adjacency-bond 实现 epic 落地。
# 现仅声明 class_name 以便 CrewDefinition 的 Array[NamedPairOverride] 解析。
class_name NamedPairOverride
extends Resource

@export var partner_id: String       # 配对方 UnitDefinition.id
@export var bond_override: int       # 覆盖后的羁绊等级（具体语义见 adjacency-bond GDD）
