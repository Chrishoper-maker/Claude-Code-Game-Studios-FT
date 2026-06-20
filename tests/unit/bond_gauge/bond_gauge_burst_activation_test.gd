# BondGaugeBurst 爆发激活测试（bond-gauge-burst GDD Rule 5 资格 / Rule 6 执行 / Rule 7 路由）。
# DI 注入真实 TurnManager + BattleResolution（破阵先锋效果走解算层）。
# 相邻判定走 GridBoard.chebyshev（静态，取自 UnitInstance.grid_position）。
# TDD：先于实现写就。
extends GdUnitTestSuite

var _bg: BondGaugeBurst
var _br: BattleResolution
var _gb: GridBoard
var _tm: TurnManager
var _uid_counter: int

func before_test() -> void:
	_gb = auto_free(GridBoard.new())
	_tm = auto_free(TurnManager.new())
	_br = auto_free(BattleResolution.new())
	_br.setup(_gb, _tm)
	_bg = auto_free(BondGaugeBurst.new())
	_bg.setup(_gb, _tm, _br)
	_uid_counter = 0

func _add(unit_class: String, faction: String, pos: Vector2i, base_damage: int = 3, max_hp: int = 10, attack_range: int = 1) -> int:
	_uid_counter += 1
	var d := UnitDefinition.new()
	d.id = "u%d" % _uid_counter
	d.faction = faction
	d.unit_class = unit_class
	d.base_damage = base_damage
	d.attack_range = attack_range
	d.max_hp = max_hp
	d.class_action_id = "v"            # 非空 → has_used_verb 初始 false（可作 partner）
	var inst := UnitInstance.from_definition(d)
	inst.grid_position = pos
	var bid := _tm.register_unit(inst)
	_gb.place_unit(bid, pos)
	return bid

# 充满羁绊槽（5×相邻攻击充能 = 10）
func _fill_gauge() -> void:
	for i in 5:
		_bg.apply_attack_charge(0, true)

# ── Rule 5 资格 ──

func test_can_activate_when_all_conditions_met() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 2))   # 正交相邻
	_fill_gauge()
	assert_bool(_bg.can_activate_burst(lead, partner)).is_true()

# AC-16：切比雪夫斜角相邻（距离 1）合法
func test_can_activate_diagonal_adjacent() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(2, 2))   # 斜向相邻
	_fill_gauge()
	assert_bool(_bg.can_activate_burst(lead, partner)).is_true()

# AC-12：槽未满不能激活
func test_cannot_activate_when_gauge_not_full() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 2))
	for i in 4:
		_bg.apply_attack_charge(0, true)                     # 仅 8 < 10
	assert_bool(_bg.can_activate_burst(lead, partner)).is_false()

# AC-13：lead.has_acted = true 不能激活
func test_cannot_activate_when_lead_has_acted() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 2))
	_fill_gauge()
	_tm.get_unit(lead).has_acted = true
	assert_bool(_bg.can_activate_burst(lead, partner)).is_false()

# AC-14：partner.has_used_verb = true 不能激活
func test_cannot_activate_when_partner_has_used_verb() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 2))
	_fill_gauge()
	_tm.get_unit(partner).has_used_verb = true
	assert_bool(_bg.can_activate_burst(lead, partner)).is_false()

# AC-15：非相邻（切比雪夫 2）不能激活
func test_cannot_activate_when_not_adjacent() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 3))   # 切比雪夫 2
	_fill_gauge()
	assert_bool(_bg.can_activate_burst(lead, partner)).is_false()

# 条件 4 / EC-11：同一单位不能既是 lead 又是 partner
func test_cannot_activate_when_same_unit() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	_fill_gauge()
	assert_bool(_bg.can_activate_burst(lead, lead)).is_false()

# 阵营过滤：lead 非友方不能激活
func test_cannot_activate_when_lead_not_ally() -> void:
	var lead := _add("swordsman", "enemy", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 2))
	_fill_gauge()
	assert_bool(_bg.can_activate_burst(lead, partner)).is_false()

# ── Rule 6 执行 ──

# AC-12：不合格激活返回 false 且槽不清零
func test_activate_returns_false_and_preserves_gauge_when_ineligible() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 3))   # 不相邻
	_fill_gauge()
	assert_bool(_bg.activate_burst(lead, partner)).is_false()
	assert_int(_bg.get_gauge_value()).is_equal(10)           # 槽保留

# AC-17：成功执行后槽清零，返回 true
func test_activate_zeroes_gauge_on_success() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 2))
	_fill_gauge()
	assert_bool(_bg.activate_burst(lead, partner)).is_true()
	assert_int(_bg.get_gauge_value()).is_equal(0)

# AC-18：消耗 lead.has_acted，不消耗 lead.has_used_verb
func test_activate_marks_lead_has_acted_not_used_verb() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 2))
	_fill_gauge()
	_bg.activate_burst(lead, partner)
	assert_bool(_tm.get_unit(lead).has_acted).is_true()
	assert_bool(_tm.get_unit(lead).has_used_verb).is_false()

# AC-19：消耗 partner.has_used_verb，不消耗 partner.has_acted
func test_activate_marks_partner_has_used_verb_not_acted() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 2))
	_fill_gauge()
	_bg.activate_burst(lead, partner)
	assert_bool(_tm.get_unit(partner).has_used_verb).is_true()
	assert_bool(_tm.get_unit(partner).has_acted).is_false()

# AC-17：发出 burst_executed(lead, partner)
func test_activate_emits_burst_executed() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 2))
	_fill_gauge()
	var captured := [-1, -1]
	var cb := func(l: int, p: int) -> void:
		captured[0] = l
		captured[1] = p
	EventBus.burst_executed.connect(cb)
	_bg.activate_burst(lead, partner)
	EventBus.burst_executed.disconnect(cb)
	assert_int(captured[0]).is_equal(lead)
	assert_int(captured[1]).is_equal(partner)

# AC-17：发出 burst_presentation_requested(lead, partner, effect_id)
func test_activate_emits_presentation_requested_with_effect_id() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 2))
	_fill_gauge()
	var captured := [&""]
	var cb := func(_l: int, _p: int, eid: StringName) -> void:
		captured[0] = eid
	EventBus.burst_presentation_requested.connect(cb)
	_bg.activate_burst(lead, partner)
	EventBus.burst_presentation_requested.disconnect(cb)
	assert_str(captured[0]).is_equal(BondGaugeBurst.BURST_VANGUARD_BREACH)

# ── Rule 7 效果路由 ──

# AC-20：剑豪+铁壁 → 破阵先锋
func test_effect_id_swordsman_bulwark_is_vanguard_breach() -> void:
	assert_str(_bg.get_burst_effect_id("swordsman", "bulwark")).is_equal(BondGaugeBurst.BURST_VANGUARD_BREACH)

# AC-22：配对对称（调换 lead/partner 同效果）
func test_effect_id_is_symmetric() -> void:
	assert_str(_bg.get_burst_effect_id("bulwark", "swordsman")).is_equal(BondGaugeBurst.BURST_VANGUARD_BREACH)

# AC-21（id）：炮手+航海士 → 瞄准定位
func test_effect_id_gunner_navigator_is_guided_salvo() -> void:
	assert_str(_bg.get_burst_effect_id("gunner", "navigator")).is_equal(BondGaugeBurst.BURST_GUIDED_SALVO)

# 非精英配对 → 通用 Combined Strike
func test_effect_id_non_elite_is_combined_strike() -> void:
	assert_str(_bg.get_burst_effect_id("swordsman", "gunner")).is_equal(BondGaugeBurst.BURST_COMBINED_STRIKE)

# ── Rule 7 破阵先锋（MVP）端到端 ──

# AC-20：铁壁获得 GUARDED
func test_vanguard_breach_bulwark_gains_guarded() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1))
	var partner := _add("bulwark", "crew", Vector2i(1, 0))   # 与剑豪相邻
	_add("enemy", "enemy", Vector2i(1, 2), 3, 10)            # 剑豪相邻敌方
	_fill_gauge()
	_bg.activate_burst(lead, partner)
	assert_bool(_br.get_unit_status(partner, BattleResolution.STATUS_GUARDED)).is_true()

# AC-20：剑豪对相邻敌方造成 base × BURST_DAMAGE_MULTIPLIER（穿透）
func test_vanguard_breach_swordsman_hits_adjacent_enemy_multiplied() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1), 3) # base 3
	var partner := _add("bulwark", "crew", Vector2i(1, 0))
	var enemy := _add("enemy", "enemy", Vector2i(1, 2), 3, 10)
	_fill_gauge()
	_bg.activate_burst(lead, partner)
	assert_int(_tm.get_unit(enemy).current_hp).is_equal(4)   # 10 - 6

# AC-22：对称——lead = 铁壁, partner = 剑豪，剑豪仍施斩、铁壁仍获 GUARDED
func test_vanguard_breach_symmetric_lead_bulwark() -> void:
	var bulwark := _add("bulwark", "crew", Vector2i(1, 0))
	var swordsman := _add("swordsman", "crew", Vector2i(1, 1), 3)
	var enemy := _add("enemy", "enemy", Vector2i(1, 2), 3, 10)
	_fill_gauge()
	_bg.activate_burst(bulwark, swordsman)                   # lead=铁壁, partner=剑豪
	assert_bool(_br.get_unit_status(bulwark, BattleResolution.STATUS_GUARDED)).is_true()
	assert_int(_tm.get_unit(enemy).current_hp).is_equal(4)   # 剑豪施斩，敌方 -6

# ── Rule 7 瞄准定位（Guided Salvo，MVP）端到端 ──

# AC-21：航海士推移相邻敌方 → 炮手朝其方向发穿透炮（base×倍率）
func test_guided_salvo_displaces_enemy_and_fires() -> void:
	var navigator := _add("navigator", "crew", Vector2i(0, 1))
	var gunner := _add("gunner", "crew", Vector2i(0, 0), 2, 10, 4)  # 与航海士相邻；base 2 range 4
	var enemy := _add("x", "enemy", Vector2i(1, 0), 3, 10)          # 航海士相邻敌方
	_fill_gauge()
	_bg.activate_burst(navigator, gunner)
	assert_vector(_tm.get_unit(enemy).grid_position).is_equal(Vector2i(3, 0))  # 推 2 格
	assert_int(_tm.get_unit(enemy).current_hp).is_equal(6)                     # 10 - 2×2

# EC-6：航海士无相邻敌方 → 推移失败 → 炮弹取消（爆发仍消耗：槽清零 + 动作点）
func test_guided_salvo_cancels_when_no_adjacent_enemy() -> void:
	var navigator := _add("navigator", "crew", Vector2i(0, 1))
	var gunner := _add("gunner", "crew", Vector2i(0, 0), 2, 10, 4)  # 相邻
	var far_enemy := _add("x", "enemy", Vector2i(7, 7), 3, 10)      # 不相邻航海士
	_fill_gauge()
	_bg.activate_burst(navigator, gunner)
	assert_int(_bg.get_gauge_value()).is_equal(0)                  # 爆发已执行
	assert_bool(_tm.get_unit(navigator).has_acted).is_true()
	assert_bool(_tm.get_unit(gunner).has_used_verb).is_true()
	assert_int(_tm.get_unit(far_enemy).current_hp).is_equal(10)    # 炮弹取消，未受伤

# ── Rule 7 通用 Combined Strike（OQ-3 裁决：动词自动选靶=最近敌人）──

# 双剑豪：各自斩相邻敌方（原版伤害 ×1，不加成）
func test_combined_strike_double_swordsman_both_slash() -> void:
	var lead := _add("swordsman", "crew", Vector2i(3, 3), 3)
	var partner := _add("swordsman", "crew", Vector2i(3, 4), 3)   # 与 lead 相邻
	var e1 := _add("x", "enemy", Vector2i(3, 2), 3, 7)            # 仅邻 lead
	var e2 := _add("y", "enemy", Vector2i(3, 5), 3, 7)            # 仅邻 partner
	_fill_gauge()
	_bg.activate_burst(lead, partner)
	assert_int(_tm.get_unit(e1).current_hp).is_equal(4)           # -3
	assert_int(_tm.get_unit(e2).current_hp).is_equal(4)           # -3

# 炮手+铁壁：炮手朝最近敌方穿透（×1），铁壁自身获 GUARDED
func test_combined_strike_gunner_fires_nearest_bulwark_self_guards() -> void:
	var lead := _add("gunner", "crew", Vector2i(0, 0), 3, 10, 3)  # range 3
	var partner := _add("bulwark", "crew", Vector2i(0, 1))        # 与炮手相邻
	var enemy := _add("x", "enemy", Vector2i(3, 0), 3, 10)        # 炮手同行净弹道
	_fill_gauge()
	_bg.activate_burst(lead, partner)
	assert_int(_tm.get_unit(enemy).current_hp).is_equal(7)        # 炮手 base 3 ×1
	assert_bool(_br.get_unit_status(partner, BattleResolution.STATUS_GUARDED)).is_true()

# EC-8：Combined Strike 的斩/轰不重新充能（清零后保持 0）
func test_combined_strike_does_not_recharge_gauge() -> void:
	var lead := _add("gunner", "crew", Vector2i(0, 0), 3, 10, 3)
	var partner := _add("bulwark", "crew", Vector2i(0, 1))
	_add("x", "enemy", Vector2i(3, 0), 3, 10)
	_fill_gauge()
	_bg.activate_burst(lead, partner)
	assert_int(_bg.get_gauge_value()).is_equal(0)

# ── Rule 7 四个 Alpha 精英爆发端到端 ──

# 热血演奏（剑豪+乐手）：乐手 aura 相邻友方 → 剑豪斩 ×倍率 + AURA_VALUE（EC-12）
func test_bardic_fury_aura_boosts_swordsman_slash() -> void:
	var sword := _add("swordsman", "crew", Vector2i(1, 1), 3)
	var musician := _add("musician", "crew", Vector2i(1, 2))   # 与剑豪相邻
	var enemy := _add("x", "enemy", Vector2i(1, 0), 3, 10)      # 剑豪相邻敌方
	_fill_gauge()
	_bg.activate_burst(sword, musician)
	assert_int(_tm.get_unit(enemy).current_hp).is_equal(3)      # 10 - (3×2 + 1)

# 轰鸣序曲（炮手+乐手）：炮手向 4 基本方向各发穿透炮 ×倍率
func test_thunder_aria_gunner_fires_four_cardinals() -> void:
	var gunner := _add("gunner", "crew", Vector2i(3, 3), 3, 10, 4)
	var musician := _add("musician", "crew", Vector2i(4, 4))    # 斜向相邻（避开炮口直线）
	var e_up := _add("x", "enemy", Vector2i(3, 1), 3, 10)
	var e_right := _add("y", "enemy", Vector2i(5, 3), 3, 10)
	_fill_gauge()
	_bg.activate_burst(gunner, musician)
	assert_int(_tm.get_unit(e_up).current_hp).is_equal(4)       # 10 - 3×2
	assert_int(_tm.get_unit(e_right).current_hp).is_equal(4)

# 护持突破（剑豪+医师）：剑豪斩 ×倍率 → 医师愈剑豪 HEAL_AMOUNT×BURST_HEAL_MULTIPLIER
func test_lifeline_slash_slashes_then_heals_swordsman() -> void:
	var sword := _add("swordsman", "crew", Vector2i(1, 1), 3, 10)
	var medic := _add("medic", "crew", Vector2i(1, 2))
	var enemy := _add("x", "enemy", Vector2i(1, 0), 3, 10)
	_tm.get_unit(sword).current_hp = 4
	_fill_gauge()
	_bg.activate_burst(sword, medic)
	assert_int(_tm.get_unit(enemy).current_hp).is_equal(4)      # 10 - 3×2
	assert_int(_tm.get_unit(sword).current_hp).is_equal(10)     # 4 + 3×2 → clamp 10

# 钢铁壁垒（铁壁+医师）：全体友方获 GUARDED + 各愈 HEAL_AMOUNT
func test_iron_sanctum_guards_and_heals_all_allies() -> void:
	var bulwark := _add("bulwark", "crew", Vector2i(1, 1), 2, 12)
	var medic := _add("medic", "crew", Vector2i(1, 2), 1, 9)
	var far := _add("swordsman", "crew", Vector2i(5, 5), 3, 10)
	_tm.get_unit(far).current_hp = 4
	_fill_gauge()
	_bg.activate_burst(bulwark, medic)
	assert_bool(_br.get_unit_status(bulwark, BattleResolution.STATUS_GUARDED)).is_true()
	assert_bool(_br.get_unit_status(medic, BattleResolution.STATUS_GUARDED)).is_true()
	assert_bool(_br.get_unit_status(far, BattleResolution.STATUS_GUARDED)).is_true()
	assert_int(_tm.get_unit(far).current_hp).is_equal(7)        # 4 + HEAL_AMOUNT(3)
