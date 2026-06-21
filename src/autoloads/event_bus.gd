# 全局事件总线（ADR-0001）。所有跨系统通信经此静态类型化信号路由。
# 注册名 EventBus，必须是 project.godot [autoload] 第一条（先于任何场景节点 _ready）。
# 系统经 EventBus.signal.connect(callable) 订阅、EventBus.signal.emit(args) 发射；
# 不持有彼此 @onready 引用。唯一直连例外：AdjacencyBond → BattleResolution.register_attack_modifier()。
#
# ⚠️ ID 二元性（ADR-0001）：attacker_id 系列为 String（UnitDefinition 资源键）；
#   unit_id 系列为 int（运行时 UnitInstance 句柄）。两套体系不可混用。
# ⚠️ 信号参数类型注解在 emit 侧不强制（Godot #110573）——单元测试须主动断言实际类型。
extends Node

# ── 战斗信号 ──
signal attack_initiated(attacker_id: String, verb: String)          # verb 供 AdjacencyBond 过滤触发
signal attack_executed(attacker_id: int, target_id: int, damage: int)
signal damage_dealt(target_id: int, final_damage: int, new_hp: int)  # 后处理后伤害与残余 HP
signal unit_downed(unit_id: int)
signal heal_executed(target_id: int, amount: int)
signal guard_applied(unit_id: int)
signal aura_performed(caster_id: String, buffed_ids: Array[int], aura_value: int)
signal slash_executed(attacker_id: String, target_ids: Array[int], pre_guard_damage: int)
signal cannon_executed(attacker_id: String, direction: int, hit_target_ids: Array[int], base_fire_damage: int)
signal displacement_executed(unit_id: int, from_pos: Vector2i, to_pos: Vector2i)
signal unit_moved(unit_id: int, from_pos: Vector2i, to_pos: Vector2i)
signal terrain_changed(pos: Vector2i, type: String)

# ── 回合信号 ──
signal battle_started()
signal battle_won()
signal battle_lost()
signal round_started(round_count: int)
signal round_ended()
signal player_phase_started()   # 阶段制：我方回合开始（玩家自由点选指挥己方单位）
signal enemy_phase_started()    # 阶段制：敌方回合开始（敌方依次自动行动）
signal unit_turn_started(unit_id: int)
signal unit_turn_ended(unit_id: int)
signal enemy_turn_started(unit_id: int)
signal enemy_actions_completed(unit_id: int)
signal last_round_warning(round_count: int)
signal intent_declared(unit_id: int, intent: IntentRecord)

# ── 羁绊/爆发信号 ──
signal gauge_charged(attacker_id: String, charge_amount: int, bond_gauge_current: int)
signal bond_gauge_full()
signal burst_executed(lead_id: int, partner_id: int)
signal burst_presentation_requested(lead_id: int, partner_id: int, effect_id: StringName)
signal burst_presentation_started()
signal burst_presentation_ended()

# ── Run 信号 ──
signal run_phase_changed(phase: String)
signal crew_member_downed(crew_id: String)
signal run_completed(won: bool, island_count: int, roster_snapshot: Array)
signal map_loaded(map_id: String)
signal map_reset_requested()
signal map_load_failed(reason: StringName)
