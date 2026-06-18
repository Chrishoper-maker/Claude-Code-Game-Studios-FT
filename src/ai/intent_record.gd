# 敌人意图记录（enemy-ai-intent-system；被 EventBus.intent_declared 信号引用，ADR-0001）。
# foundation 类型：字段足以支撑信号契约与 HUD 明示；完整生成/过期逻辑由 enemy-ai epic 落地。
# ADR-0001 要求本类声明 class_name，否则 EventBus 须 preload 本脚本。
class_name IntentRecord
extends Resource

enum IntentType { INTENT_WAIT, INTENT_MOVE, INTENT_ATTACK, INTENT_MOVE_ATTACK }

@export var unit_id: int
@export var intent_type: IntentType = IntentType.INTENT_WAIT
@export var target_id: int = -1            # 攻击目标运行时 id（无则 -1）
@export var target_pos: Vector2i           # 移动/攻击落点
