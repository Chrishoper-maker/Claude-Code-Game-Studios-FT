# 船员定义（玩家方单位模板，继承 UnitDefinition，ADR-0003）。
class_name CrewDefinition
extends UnitDefinition

@export var title: String
@export var battle_cry: String                            # 招募卡台词（≤24 字，route-recruitment-ui）
@export var persona_line: String
@export_enum("starting", "pool", "unlockable") var recruit_pool_tier: String
@export var portrait_id: String
@export var model_id: String
@export var named_pair_overrides: Array[NamedPairOverride]
