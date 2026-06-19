# BattleMap 验证内核测试（battle-map-system GDD Rule 3 验证序列 ①–⑨ / 公式 F1–F6）。
# 纯逻辑：validate_map(map_def, unit_lookup) → 失败 reason 或 &"" 成功。
# unit_lookup 注入（DI，coding-standards），避免依赖 UnitDataManager autoload 与 .tres。
# 部署阶段（地形写入/UnitInstance 生成/place）需 UnitInstance 类，未建，不在此测。
# TDD：先于实现写就。
extends GdUnitTestSuite

func _bm() -> BattleMap:
	return auto_free(BattleMap.new())

# ── 测试数据构造器 ──

func _cell(pos: Vector2i, type: String = "BLOCKED") -> TerrainCell:
	var c := TerrainCell.new()
	c.pos = pos
	c.type = type
	return c

func _slot(id: String, pos: Vector2i, behavior: String = "MELEE", home := Vector2i(-1, -1)) -> EnemySlotDefinition:
	var s := EnemySlotDefinition.new()
	s.unit_definition_id = id
	s.grid_position = pos
	s.behavior_type = behavior
	s.home_pos = home
	return s

# 默认查找：已知 4 个敌人 id 全 threat_tier=1；未知 id 返回 null。
func _lookup_tier1() -> Callable:
	var defs := {}
	for id in ["e_melee", "e_ranged", "e_swarm", "e_guard"]:
		var d := EnemyDefinition.new()
		d.id = id
		d.threat_tier = 1
		defs[id] = d
	return func(id: String) -> UnitDefinition: return defs.get(id, null)

# 通过全部 F1–F6 的基线地图（参照 battle_map_001 结构）。
func _valid_map() -> MapDefinition:
	var m := MapDefinition.new()
	m.map_id = "test_map"
	m.island_tier = 1
	m.terrain_data = [_cell(Vector2i(1, 1)), _cell(Vector2i(1, 2)), _cell(Vector2i(5, 1)), _cell(Vector2i(5, 2))]
	var dz: Array[Vector2i] = []
	for x in range(0, 6):
		dz.append(Vector2i(x, 6))
		dz.append(Vector2i(x, 7))
	m.deploy_zone = dz  # 12 格，无 BLOCKED 重叠
	m.enemy_roster = [
		_slot("e_melee", Vector2i(2, 0), "MELEE"),
		_slot("e_ranged", Vector2i(7, 0), "RANGED"),
		_slot("e_swarm", Vector2i(3, 3), "SWARMER"),      # 距 (3,6) manhattan=3 = 最小分离下界
		_slot("e_guard", Vector2i(7, 3), "GUARDIAN", Vector2i(7, 3)),
	]
	return m

func _validate(m: MapDefinition) -> String:
	return str(_bm().validate_map(m, _lookup_tier1()))

# ── 基线 ──

func test_valid_map_passes() -> void:
	assert_str(_validate(_valid_map())).is_equal("")

# ── F1 地形密度（AC-4）──

func test_terrain_density_exceeded() -> void:
	var m := _valid_map()
	var t: Array[TerrainCell] = []
	for i in 17:
		t.append(_cell(Vector2i(i % 8, 4 + i / 8)))  # 17 BLOCKED 格 > 16
	m.terrain_data = t
	assert_str(_validate(m)).contains("terrain_density_exceeded")

# ── F3 敌方数量（AC-5/6/18/19）──

func test_enemy_count_below_minimum() -> void:
	var m := _valid_map()
	m.enemy_roster = [_slot("e_melee", Vector2i(2, 0))]
	assert_str(_validate(m)).contains("enemy_count_below_minimum")

func test_enemy_count_above_maximum() -> void:
	var m := _valid_map()
	var r: Array[EnemySlotDefinition] = []
	for i in 7:
		r.append(_slot("e_melee", Vector2i(i, 0)))
	m.enemy_roster = r
	assert_str(_validate(m)).contains("enemy_count_above_maximum")

func test_enemy_count_min_boundary_passes() -> void:
	var m := _valid_map()
	m.enemy_roster = [
		_slot("e_melee", Vector2i(2, 0)),
		_slot("e_swarm", Vector2i(3, 3), "SWARMER"),
	]
	assert_str(_validate(m)).is_equal("")

func test_enemy_count_max_boundary_passes() -> void:
	var m := _valid_map()
	m.enemy_roster = [
		_slot("e_melee", Vector2i(0, 0)), _slot("e_melee", Vector2i(2, 0)),
		_slot("e_ranged", Vector2i(4, 0), "RANGED"), _slot("e_ranged", Vector2i(6, 0), "RANGED"),
		_slot("e_swarm", Vector2i(3, 3), "SWARMER"), _slot("e_guard", Vector2i(7, 3), "GUARDIAN"),
	]
	assert_str(_validate(m)).is_equal("")

# ── 敌方起始格冲突（AC-7）──

func test_enemy_position_collision() -> void:
	var m := _valid_map()
	m.enemy_roster = [
		_slot("e_melee", Vector2i(3, 3)),
		_slot("e_swarm", Vector2i(3, 3), "SWARMER"),
	]
	assert_str(_validate(m)).contains("enemy_position_collision")

# ── 敌方起始格落在 BLOCKED（EC-3）──

func test_enemy_start_on_blocked() -> void:
	var m := _valid_map()
	m.enemy_roster = [
		_slot("e_melee", Vector2i(1, 1)),                 # (1,1) 是 BLOCKED
		_slot("e_swarm", Vector2i(3, 3), "SWARMER"),
	]
	assert_str(_validate(m)).contains("enemy_start_blocked")

# ── F2 部署区有效格数（EC-1 / AC-10）──

func test_deploy_zone_insufficient() -> void:
	var m := _valid_map()
	m.deploy_zone = [Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6)]  # 仅 5 格
	assert_str(_validate(m)).contains("deploy_zone_insufficient")

func test_deploy_overlap_reduces_but_still_passes() -> void:
	var m := _valid_map()
	# 8 格部署区，其中 2 格落在 BLOCKED (1,1)(1,2) → 有效 6 格 ≥ 6
	m.deploy_zone = [
		Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6),
		Vector2i(0, 7), Vector2i(2, 7), Vector2i(1, 1), Vector2i(1, 2),
	]
	assert_str(_validate(m)).is_equal("")

# ── F4 最小分离距离（AC-8 / AC-20）──

func test_separation_violated() -> void:
	var m := _valid_map()
	# 敌人 (0,5) 距部署区 (0,6) manhattan=1 < 3
	m.enemy_roster = [
		_slot("e_melee", Vector2i(0, 5)),
		_slot("e_swarm", Vector2i(3, 3), "SWARMER"),
	]
	assert_str(_validate(m)).contains("separation_constraint_violated")

func test_separation_boundary_three_passes() -> void:
	var m := _valid_map()
	# 敌人 (3,3) 距 (3,6) = 3 恰好满足；另一个远离
	m.enemy_roster = [
		_slot("e_swarm", Vector2i(3, 3), "SWARMER"),
		_slot("e_melee", Vector2i(7, 0)),
	]
	assert_str(_validate(m)).is_equal("")

# ── F7 未知 unit_definition_id（AC-11 / EC-6）──

func test_unknown_unit_definition() -> void:
	var m := _valid_map()
	m.enemy_roster = [
		_slot("e_does_not_exist", Vector2i(2, 0)),
		_slot("e_swarm", Vector2i(3, 3), "SWARMER"),
	]
	assert_str(_validate(m)).contains("unknown_unit_definition")

# ── F5 威胁层级匹配（AC-12）──

func test_threat_tier_mismatch() -> void:
	var m := _valid_map()
	# island_tier=1 仅允许 threat_tier {1}；注入一个 tier=2 的敌人
	var lookup := func(id: String) -> UnitDefinition:
		var d := EnemyDefinition.new()
		d.id = id
		d.threat_tier = 2
		return d
	assert_str(str(_bm().validate_map(m, lookup))).contains("threat_tier_mismatch")

# ── 短路顺序：密度先于数量 ──

func test_short_circuit_density_before_count() -> void:
	var m := _valid_map()
	var t: Array[TerrainCell] = []
	for i in 17:
		t.append(_cell(Vector2i(i % 8, 4 + i / 8)))
	m.terrain_data = t
	m.enemy_roster = [_slot("e_melee", Vector2i(2, 0))]  # 同时数量不足
	assert_str(_validate(m)).contains("terrain_density_exceeded")  # 密度先报

# ── F6 远程走廊检测（AC-14）──

func test_corridor_empty_board_true() -> void:
	# 空棋盘：行 0 为边界行，长度 8 ≥ 3 → 走廊成立
	assert_bool(_bm().has_valid_ranged_corridor([] as Array[Vector2i])).is_true()

func test_corridor_surrounded_pocket_false() -> void:
	# 仅中央 2×2 开放、其余全 BLOCKED：无任何 ≥3 连续非 BLOCKED 序列 → 无走廊
	var open := {Vector2i(3, 3): true, Vector2i(4, 3): true, Vector2i(3, 4): true, Vector2i(4, 4): true}
	var blocked: Array[Vector2i] = []
	for x in 8:
		for y in 8:
			if not open.has(Vector2i(x, y)):
				blocked.append(Vector2i(x, y))
	assert_bool(_bm().has_valid_ranged_corridor(blocked)).is_false()
