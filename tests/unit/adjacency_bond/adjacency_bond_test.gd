# AdjacencyBond 测试（adjacency-bond-system GDD Rule 1-3 + BOND_MATRIX）。
# 订阅 attack_initiated → 阵营/动词过滤 → 查矩阵 → register_attack_modifier 注入。
# DI 注入真实 GridBoard + TurnManager + BattleResolution；经 get_pending_modifier 观测注入。
# TDD：先于实现写就。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _ab: AdjacencyBond
var _uid_counter: int

func before_test() -> void:
	_gb = auto_free(GridBoard.new())
	_tm = auto_free(TurnManager.new())
	_br = auto_free(BattleResolution.new())
	_br.setup(_gb, _tm)
	_ab = auto_free(AdjacencyBond.new())
	_ab.setup(_gb, _tm, _br)
	_uid_counter = 0

func _add(faction: String, unit_class: String, pos: Vector2i) -> int:
	_uid_counter += 1
	var d := UnitDefinition.new()
	d.id = "u%d" % _uid_counter
	d.faction = faction
	d.unit_class = unit_class
	d.max_hp = 6
	var inst := UnitInstance.from_definition(d)
	inst.grid_position = pos
	var bid := _tm.register_unit(inst)
	_gb.place_unit(bid, pos)
	return bid

# 通用羁绊 +1（剑豪+炮手，非精英对）
func test_base_bond_injects_one() -> void:
	var a := _add("crew", "swordsman", Vector2i(1, 1))
	_add("crew", "gunner", Vector2i(1, 2))
	_ab.on_attack_initiated(str(a), "normal_attack")
	assert_int(_br.get_pending_modifier(a)).is_equal(1)

# 精英羁绊 +2（剑豪+乐手）
func test_elite_bond_injects_two() -> void:
	var a := _add("crew", "swordsman", Vector2i(1, 1))
	_add("crew", "musician", Vector2i(1, 2))
	_ab.on_attack_initiated(str(a), "normal_attack")
	assert_int(_br.get_pending_modifier(a)).is_equal(2)

# 精英羁绊 +2（炮手+航海士）
func test_elite_bond_gunner_navigator() -> void:
	var a := _add("crew", "gunner", Vector2i(1, 1))
	_add("crew", "navigator", Vector2i(1, 2))
	_ab.on_attack_initiated(str(a), "normal_attack")
	assert_int(_br.get_pending_modifier(a)).is_equal(2)

# 敌方攻击者不触发注入
func test_enemy_attacker_no_injection() -> void:
	var a := _add("enemy", "swordsman", Vector2i(1, 1))
	_add("crew", "musician", Vector2i(1, 2))
	_ab.on_attack_initiated(str(a), "normal_attack")
	assert_int(_br.get_pending_modifier(a)).is_equal(0)

# 非触发动词不注入
func test_non_trigger_verb_no_injection() -> void:
	var a := _add("crew", "swordsman", Vector2i(1, 1))
	_add("crew", "musician", Vector2i(1, 2))
	_ab.on_attack_initiated(str(a), "guard")
	assert_int(_br.get_pending_modifier(a)).is_equal(0)

# 仅己方相邻计入（敌方相邻不贡献）
func test_only_ally_neighbors_count() -> void:
	var a := _add("crew", "swordsman", Vector2i(1, 1))
	_add("enemy", "musician", Vector2i(0, 0))       # 敌方相邻，忽略
	_add("crew", "gunner", Vector2i(1, 2))          # 友方相邻，+1
	_ab.on_attack_initiated(str(a), "normal_attack")
	assert_int(_br.get_pending_modifier(a)).is_equal(1)

# 多名相邻友方累加（精英2 + 通用1 = 3，由战斗解算截断；本系统注入原始和）
func test_multiple_allies_sum_uncapped() -> void:
	var a := _add("crew", "swordsman", Vector2i(1, 1))
	_add("crew", "musician", Vector2i(1, 2))        # 精英 +2
	_add("crew", "gunner", Vector2i(2, 1))          # 通用 +1
	_ab.on_attack_initiated(str(a), "normal_attack")
	assert_int(_br.get_pending_modifier(a)).is_equal(3)

# 斩同样触发
func test_slash_verb_triggers() -> void:
	var a := _add("crew", "swordsman", Vector2i(1, 1))
	_add("crew", "musician", Vector2i(1, 2))
	_ab.on_attack_initiated(str(a), "slash")
	assert_int(_br.get_pending_modifier(a)).is_equal(2)

# 阵亡的相邻友方不计入
func test_dead_neighbor_ignored() -> void:
	var a := _add("crew", "swordsman", Vector2i(1, 1))
	var dead := _add("crew", "musician", Vector2i(1, 2))
	_tm.get_unit(dead).is_alive = false
	_ab.on_attack_initiated(str(a), "normal_attack")
	assert_int(_br.get_pending_modifier(a)).is_equal(0)

# 订阅 EventBus 生效（setup 中连线）
func test_eventbus_subscription_wired() -> void:
	var a := _add("crew", "swordsman", Vector2i(1, 1))
	_add("crew", "medic", Vector2i(1, 2))           # 剑豪+医师 精英 +2
	EventBus.attack_initiated.emit(str(a), "normal_attack")
	assert_int(_br.get_pending_modifier(a)).is_equal(2)
