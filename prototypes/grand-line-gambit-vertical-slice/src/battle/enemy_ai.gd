# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: 简单确定性敌人意图（MELEE 贪心逼近 + 明示意图）
# Date: 2026-06-18
#
# 敌人 AI（切片：单一 MELEE 行为原型）。确定性贪心——逼近最近船员并攻击。
# 返回意图供 HUD 明示 + 供 controller 执行。
class_name EnemyAI
extends RefCounted

# 找最近的存活船员（曼哈顿；平手取 instance_id 小者，确定性）
static func nearest_crew(enemy: UnitInstance, units: Dictionary) -> UnitInstance:
	var best: UnitInstance = null
	var best_d: int = 1 << 30
	var best_id: int = 1 << 30
	for id in units:
		var u: UnitInstance = units[id]
		if not u.is_alive or u.faction() != "crew":
			continue
		var d := GridBoard.manhattan(enemy.grid_position, u.grid_position)
		if d < best_d or (d == best_d and u.instance_id < best_id):
			best_d = d
			best_id = u.instance_id
			best = u
	return best

# 计算意图：目标船员 + 是否本回合可攻击
static func intent_for(enemy: UnitInstance, units: Dictionary) -> Dictionary:
	var target := nearest_crew(enemy, units)
	if target == null:
		return {"target_id": -1, "will_attack": false}
	var dist := GridBoard.chebyshev(enemy.grid_position, target.grid_position)
	return {"target_id": target.instance_id, "will_attack": dist <= enemy.definition.attack_range}

# 选择朝目标的下一步落点（reachable 中最小化到目标曼哈顿；平手取确定性最小坐标）
static func step_toward(enemy: UnitInstance, target_pos: Vector2i, board: GridBoard) -> Vector2i:
	var cells := board.reachable_cells(enemy.grid_position, enemy.definition.move_range)
	var best := enemy.grid_position
	var best_d := GridBoard.manhattan(enemy.grid_position, target_pos)
	for c in cells:
		var d := GridBoard.manhattan(c, target_pos)
		if d < best_d or (d == best_d and _coord_less(c, best)):
			best_d = d
			best = c
	return best

static func _coord_less(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
