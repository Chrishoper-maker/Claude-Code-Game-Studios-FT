# 羁绊槽 + 爆发技（architecture.md §144 / bond-gauge-burst-system）。
# 共享槽 BOND_GAUGE_MAX=10、跨回合保留、不跨战斗保留。
# 充能核心（Rule 1-4）已实现；爆发激活（Rule 5-6）需 UnitInstance，留 TODO。
class_name BondGaugeBurst
extends Node

# 旋钮常量（bond-gauge-burst-system §Tuning Knobs / entities.yaml）。
const BOND_GAUGE_MAX := 10        # 槽上限（原型验证值，不可随意调低）
const CHARGE_ADJACENT := 2        # 相邻站位充能
const CHARGE_SOLO := 1            # 单独作战充能
const CHARGE_HIT := 1             # 受击充能
const RECEIVED_CHARGE_CAP := 2    # 每回合受击充能上限（压制"故意挨打"策略）

var _gauge: int = 0                       # bond_gauge_current ∈ [0, BOND_GAUGE_MAX]
var _received_charge_this_round: int = 0  # 本回合已受击充能量（ROUND_END 重置）

func get_gauge_value() -> int:
	return _gauge

func is_full() -> bool:
	return _gauge >= BOND_GAUGE_MAX

# Rule 2：普通攻击 / 斩 命中充能。相邻与否由调用方（GridBoard 计算）传入。
func apply_attack_charge(attacker_id: int, is_adjacent: bool) -> void:
	_charge(attacker_id, CHARGE_ADJACENT if is_adjacent else CHARGE_SOLO)

# Rule 3：炮手·轰每次使用充能（充能逻辑同攻击）。
func apply_cannon_charge(attacker_id: int, is_adjacent: bool) -> void:
	_charge(attacker_id, CHARGE_ADJACENT if is_adjacent else CHARGE_SOLO)

# Rule 4：己方受击充能，每回合上限 RECEIVED_CHARGE_CAP（拦截后不增计数）。
func apply_received_charge(target_id: int) -> void:
	if _received_charge_this_round >= RECEIVED_CHARGE_CAP:
		return
	_received_charge_this_round += 1
	_charge(target_id, CHARGE_HIT)

# ROUND_END：重置受击计数（不重置槽——槽跨回合保留）。
func on_round_end() -> void:
	_received_charge_this_round = 0

# 爆发执行后归零（不跨战斗保留时也调用）。
func reset_gauge() -> void:
	_gauge = 0

# 共享充能内核（Rule 1 步骤 4-7）：clamp + emit gauge_charged + 首次满槽 emit bond_gauge_full。
func _charge(source_id: int, amount: int) -> void:
	var prev := _gauge
	_gauge = mini(_gauge + amount, BOND_GAUGE_MAX)
	# gauge_charged 第一参声明 String；本系统 id 用 int（与代码库一致），emit 边界转换。
	EventBus.gauge_charged.emit(str(source_id), amount, _gauge)
	if prev < BOND_GAUGE_MAX and _gauge == BOND_GAUGE_MAX:
		EventBus.bond_gauge_full.emit()

func activate_burst(_lead_id: int, _partner_id: int) -> void:
	# TODO(bond-gauge-burst story Rule 5-6)：校验槽满 + lead/partner 切比雪夫相邻 →
	#   消耗行动点 → reset_gauge() → EventBus.burst_executed / burst_presentation_requested。
	#   需 UnitInstance（roster/行动点），待战斗解算与单位实例落地后实现。
	pass
