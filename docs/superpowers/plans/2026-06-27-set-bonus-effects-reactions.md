# 套装效果第二批：反应型三套（②b-2b）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **⚠️ 待用户批准**：本计划基于 ②b-2b 设计稿（`docs/superpowers/specs/2026-06-27-set-bonus-effects-reactions-design.md`，§10 列出无人模式自主拟定的数值/机制）。**实现前需用户复审 spec + 本计划**（尤其战斗数值）。

**Goal:** 落地三套反应型套装（嗜血/荆棘/处决），响应 `attack_executed` 触发，复用既有 heal + 新增不发 attack_executed 的反应伤害入口，杜绝递归。

**Architecture:** 新 `SetReactionSystem`（Node，订阅 `attack_executed`，照 SetEffectSystem/AdjacencyBond 模式）；新 `BattleResolution.apply_reaction_damage`（扣 hp + damage_dealt + resolve_unit_downed，**不** emit attack_executed）；嗜血复用 `execute_burst_heal`。`SetEffectCatalog` 扩三套描述。不改 SetEffectSystem、不侵入 _compute_attack_damage。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。战斗系统节点 + EventBus。

## Global Constraints

- 引擎 Godot 4.6.3；测试 GdUnit4：先 `/Applications/Godot.app/Contents/MacOS/Godot --headless --import`，再 `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a <test path>`。
- 命名：类 PascalCase、变量/函数 snake_case、常量 UPPER_SNAKE_CASE。
- GDScript 静态类型；公共/新增 API 中文 doc 注释。
- 数值用具名常量（不散落魔法数）。
- 测试 0 孤儿：Node 派生对象（GridBoard/TurnManager/BattleResolution/SetReactionSystem）须 `auto_free()` 或 after_test `free()`（含未入树的 GridBoard）。
- 提交 Conventional Commits，body 引用 `Story: set-bonus-effects-reactions`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 三套 set_id：set_bloodthirst / set_thorns / set_executioner（②b-1 数据已含，各 9 槽）。阈值 [3,6,9]，累加（升级轴取最高）。
- 反应**阵营无关**。反应伤害**绝不** emit attack_executed（防递归/二次充能，沿 ②b-2a execute_burst_slash 先例）。
- 不改 SetEffectSystem、_compute_attack_damage。

## 数值（自主拟定，待 playtest 校）

- 嗜血：3=floor(dmg/4)、6/9=floor(dmg/2)；9 档相邻八向同阵营友军另 +floor(dmg/4)。
- 荆棘：3/6/9 → 反伤 1/2/3（取最高激活档；2026-06-27 用户逐套复审下调，原拟 2/4/6）。
- 处决：3/6/9 → 阈值 3/5/7、追加 3/5/7（取最高激活档）；命中后 target.is_alive 且 hp≤阈值才触发。

## File Structure

- `src/battle/battle_resolution.gd`（改）：加 `apply_reaction_damage`。
- `src/battle/set_reaction_system.gd`（建）：Node，订阅 attack_executed，三套反应。
- `src/ui/set_effect_catalog.gd`（改）：补三套描述。
- `scenes/BattleScene.tscn` + `src/battle/battle_scene.gd`（改）：加 SetReactionSystem 节点 + 装配。
- 测试：`tests/unit/battle_resolution/`、`tests/unit/set_reactions/`、`tests/integration/set_reactions/`。

---

### Task 1: BattleResolution.apply_reaction_damage（反应伤害入口）

**Files:**
- Modify: `src/battle/battle_resolution.gd`
- Test: `tests/unit/battle_resolution/reaction_damage_test.gd` (create)

**Interfaces:**
- Produces: `apply_reaction_damage(target_id: int, amount: int) -> void`——扣 hp（钳 0）、emit `damage_dealt`、hp==0 时 `resolve_unit_downed`，**不** emit `attack_executed`。
- Consumes: 既有 `_turn_manager.get_unit`、`resolve_unit_downed`、`EventBus.damage_dealt`。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/battle_resolution/reaction_damage_test.gd`：

```gdscript
# apply_reaction_damage：扣血/钳0/致死走 downed/不发 attack_executed（防递归）。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new()
	add_child(_tm); add_child(_br)
	_br.setup(_gb, _tm)

func after_test() -> void:
	_tm.free(); _br.free(); _gb.free()

func _enemy_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is EnemyDefinition:
			return d
	return null

func _register() -> int:
	return _tm.register_unit(UnitInstance.from_definition(_enemy_def()))

func test_reaction_damage_reduces_hp() -> void:
	var id := _register()
	var u := _tm.get_unit(id)
	u.current_hp = 10
	_br.apply_reaction_damage(id, 3)
	assert_int(u.current_hp).is_equal(7)

func test_reaction_damage_clamps_to_zero_and_downs() -> void:
	var id := _register()
	var u := _tm.get_unit(id)
	u.current_hp = 2
	_br.apply_reaction_damage(id, 5)
	assert_int(u.current_hp).is_equal(0)
	assert_bool(u.is_alive).is_false()

func test_reaction_damage_does_not_emit_attack_executed() -> void:
	var id := _register()
	_tm.get_unit(id).current_hp = 10
	var spy := [0]
	EventBus.attack_executed.connect(func(_a: int, _b: int, _c: int) -> void: spy[0] += 1)
	_br.apply_reaction_damage(id, 3)
	assert_int(spy[0]).is_equal(0)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests/unit/battle_resolution/reaction_damage_test.gd`
Expected: FAIL（apply_reaction_damage 未定义）。

- [ ] **Step 3: 实现**

在 `battle_resolution.gd`（resolve_unit_downed 之后）加：

```gdscript
# 反应伤害入口（②b-2b 荆棘反伤/处决斩杀）：扣 hp、emit damage_dealt、致死走 downed。
# 绝不 emit attack_executed（防再次触发套装反应/羁绊充能；同 execute_burst_* 先例）。
func apply_reaction_damage(target_id: int, amount: int) -> void:
	var t := _turn_manager.get_unit(target_id)
	if t == null or not t.is_alive:
		return
	var new_hp := maxi(0, t.current_hp - amount)
	t.current_hp = new_hp
	EventBus.damage_dealt.emit(target_id, amount, new_hp)
	if new_hp == 0:
		resolve_unit_downed(target_id)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/battle_resolution/reaction_damage_test.gd`
Expected: PASS (3/3)。

- [ ] **Step 5: 提交**

```bash
git add src/battle/battle_resolution.gd tests/unit/battle_resolution/reaction_damage_test.gd
git commit -m "feat(battle): apply_reaction_damage (no attack_executed, anti-recursion)

Story: set-bonus-effects-reactions
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: SetReactionSystem 框架 + 嗜血 + 战斗装配

**Files:**
- Create: `src/battle/set_reaction_system.gd`
- Modify: `scenes/BattleScene.tscn`, `src/battle/battle_scene.gd`
- Test: `tests/unit/set_reactions/set_reaction_bloodthirst_test.gd` (create)

**Interfaces:**
- Consumes: `SetBonus`、`BattleResolution.execute_burst_heal`、`TurnManager.get_unit`、`GridBoard.get_adjacents`、`EventBus.attack_executed`。
- Produces:
  - `SetReactionSystem.setup(grid_board, turn_manager, battle_resolution) -> void`
  - `SetReactionSystem.on_attack_executed(attacker_id: int, target_id: int, damage: int) -> void`
  - 常量 `BLOODTHIRST_DIV_LOW`(=4) / `BLOODTHIRST_DIV_HIGH`(=2)
  - 私有 `_apply_bloodthirst`、`_adjacent_allies`

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/set_reactions/set_reaction_bloodthirst_test.gd`：

```gdscript
# 嗜血套：命中后攻击者按伤害回血（3=¼ / 6=½ / 9=½+相邻¼）。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _srs: SetReactionSystem
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new(); _srs = SetReactionSystem.new()
	add_child(_tm); add_child(_br); add_child(_srs)
	_br.setup(_gb, _tm); _srs.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _srs.free(); _gb.free()

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition: return d
	return null

func _register_set(set_short: String, k: int, pos: Vector2i) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	var u := UnitInstance.from_definition(_crew_def(), eq)
	var id := _tm.register_unit(u); u.grid_position = pos
	return id

func _register_plain(pos: Vector2i) -> int:
	var u := UnitInstance.from_definition(_crew_def(), {})
	var id := _tm.register_unit(u); u.grid_position = pos
	return id

func test_bloodthirst_3_heals_quarter() -> void:
	var aid := _register_set("bloodthirst", 3, Vector2i(0, 0))
	var a := _tm.get_unit(aid); a.current_hp = 1
	_srs.on_attack_executed(aid, _register_plain(Vector2i(5, 5)), 8)
	assert_int(a.current_hp).is_equal(mini(1 + 2, a.get_max_hp()))   # floor(8/4)=2

func test_bloodthirst_6_heals_half() -> void:
	var aid := _register_set("bloodthirst", 6, Vector2i(0, 0))
	var a := _tm.get_unit(aid); a.current_hp = 1
	_srs.on_attack_executed(aid, _register_plain(Vector2i(5, 5)), 8)
	assert_int(a.current_hp).is_equal(mini(1 + 4, a.get_max_hp()))   # floor(8/2)=4

func test_bloodthirst_9_overflows_to_adjacent() -> void:
	var aid := _register_set("bloodthirst", 9, Vector2i(0, 0))
	var ally := _register_plain(Vector2i(1, 0))   # 相邻
	var a := _tm.get_unit(aid); a.current_hp = 1
	var al := _tm.get_unit(ally); al.current_hp = 1
	_srs.on_attack_executed(aid, _register_plain(Vector2i(5, 5)), 8)
	assert_int(al.current_hp).is_equal(mini(1 + 2, al.get_max_hp()))   # 相邻 floor(8/4)=2
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/set_reactions/set_reaction_bloodthirst_test.gd`
Expected: FAIL（SetReactionSystem 未定义）。

- [ ] **Step 3: 实现 SetReactionSystem（框架 + 嗜血）**

创建 `src/battle/set_reaction_system.gd`：

```gdscript
# 套装反应引擎（②b-2b）。订阅 attack_executed，按攻击者/目标的套装档位触发反应
# （嗜血/处决看攻击者，荆棘看目标）。阵营无关。反应伤害走 apply_reaction_damage（不发
# attack_executed，防递归）；治疗走 execute_burst_heal。
class_name SetReactionSystem
extends Node

const BLOODTHIRST_DIV_LOW := 4    # 嗜血 3 档：floor(dmg/4)
const BLOODTHIRST_DIV_HIGH := 2   # 嗜血 6/9 档：floor(dmg/2)

var _grid_board: GridBoard
var _turn_manager: TurnManager
var _battle_resolution: BattleResolution

func setup(grid_board: GridBoard, turn_manager: TurnManager, battle_resolution: BattleResolution) -> void:
	_grid_board = grid_board
	_turn_manager = turn_manager
	_battle_resolution = battle_resolution
	if not EventBus.attack_executed.is_connected(on_attack_executed):
		EventBus.attack_executed.connect(on_attack_executed)

# 命中后：攻击者侧（嗜血/处决）+ 目标侧（荆棘）反应。
func on_attack_executed(attacker_id: int, target_id: int, damage: int) -> void:
	var attacker := _turn_manager.get_unit(attacker_id)
	if attacker != null and attacker.is_alive:
		if SetBonus.count_sets(attacker).has("set_bloodthirst"):
			_apply_bloodthirst(attacker_id, attacker, damage)

# 嗜血：攻击者回血 floor(dmg/4)（3档）或 floor(dmg/2)（6/9档）；9档相邻同阵营友军另 floor(dmg/4)。
func _apply_bloodthirst(attacker_id: int, attacker: UnitInstance, damage: int) -> void:
	var div := BLOODTHIRST_DIV_HIGH if SetBonus.is_tier_active(attacker, "set_bloodthirst", 6) else BLOODTHIRST_DIV_LOW
	_battle_resolution.execute_burst_heal(attacker_id, damage / div)
	if SetBonus.is_tier_active(attacker, "set_bloodthirst", 9):
		for ally_id in _adjacent_allies(attacker):
			_battle_resolution.execute_burst_heal(ally_id, damage / BLOODTHIRST_DIV_LOW)

# 相邻八向、同阵营、存活、非自身的单位 battle_id。
func _adjacent_allies(source: UnitInstance) -> Array[int]:
	var out: Array[int] = []
	for id in _grid_board.get_adjacents(source.grid_position):
		var u := _turn_manager.get_unit(id)
		if u != null and u.is_alive and u.definition.faction == source.definition.faction:
			out.append(id)
	return out
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/set_reactions/set_reaction_bloodthirst_test.gd`
Expected: PASS (3/3)。

- [ ] **Step 5: 战斗装配**

`scenes/BattleScene.tscn`：加 `SetReactionSystem` 节点（脚本 `res://src/battle/set_reaction_system.gd`），与 SetEffectSystem 同级（Node3D 根直接子节点）。参考既有 SetEffectSystem 节点的 .tscn 写法。
`src/battle/battle_scene.gd`：加 `@onready var _set_reaction_system: SetReactionSystem = $SetReactionSystem`，并在 `_ready` 装配段（SetEffectSystem.setup 之后）加 `_set_reaction_system.setup(_grid_board, _turn_manager, _battle_resolution)`。

- [ ] **Step 6: 导入 + 全量回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests`
Expected: 0 失败/错误/孤儿。

- [ ] **Step 7: 提交**

```bash
git add src/battle/set_reaction_system.gd scenes/BattleScene.tscn src/battle/battle_scene.gd tests/unit/set_reactions/set_reaction_bloodthirst_test.gd
git commit -m "feat(battle): SetReactionSystem framework + bloodthirst + wiring

Story: set-bonus-effects-reactions
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 荆棘套（反伤）

**Files:**
- Modify: `src/battle/set_reaction_system.gd`
- Test: `tests/unit/set_reactions/set_reaction_thorns_test.gd` (create)

**Interfaces:**
- Consumes: 框架 + `BattleResolution.apply_reaction_damage`（Task 1）。
- Produces: 私有 `_apply_thorns`；`on_attack_executed` 加目标侧荆棘分支；常量 `THORNS_DMG`（Dictionary {3:1,6:2,9:3}）。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/set_reactions/set_reaction_thorns_test.gd`（复用 Task 2 fixture 结构）：

```gdscript
# 荆棘套：被命中后对攻击者反伤 1/2/3；反伤不发 attack_executed（防递归）。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _srs: SetReactionSystem
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new(); _srs = SetReactionSystem.new()
	add_child(_tm); add_child(_br); add_child(_srs)
	_br.setup(_gb, _tm); _srs.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _srs.free(); _gb.free()

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition: return d
	return null

func _register_set(set_short: String, k: int) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), eq))

func _register_plain() -> int:
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), {}))

func test_thorns_3_reflects_one() -> void:
	var aid := _register_plain()
	var tid := _register_set("thorns", 3)
	var a := _tm.get_unit(aid); a.current_hp = 10
	_srs.on_attack_executed(aid, tid, 5)
	assert_int(a.current_hp).is_equal(9)   # 反伤 1

func test_thorns_9_reflects_three() -> void:
	var aid := _register_plain()
	var tid := _register_set("thorns", 9)
	var a := _tm.get_unit(aid); a.current_hp = 10
	_srs.on_attack_executed(aid, tid, 5)
	assert_int(a.current_hp).is_equal(7)   # 反伤 3

func test_thorns_reflection_emits_no_attack_executed() -> void:
	var aid := _register_plain()
	var tid := _register_set("thorns", 3)
	_tm.get_unit(aid).current_hp = 10
	var spy := [0]
	EventBus.attack_executed.connect(func(_a: int, _b: int, _c: int) -> void: spy[0] += 1)
	_srs.on_attack_executed(aid, tid, 5)
	assert_int(spy[0]).is_equal(0)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/set_reactions/set_reaction_thorns_test.gd`
Expected: FAIL（无荆棘分支 → 攻击者 hp 不变）。

- [ ] **Step 3: 实现**

`set_reaction_system.gd` 常量区加：

```gdscript
const THORNS_DMG := {3: 1, 6: 2, 9: 3}   # 荆棘反伤（按激活档取最高）
```

`on_attack_executed` 末尾加目标侧分支：

```gdscript
	var target := _turn_manager.get_unit(target_id)
	if target != null and target.is_alive and SetBonus.count_sets(target).has("set_thorns"):
		_apply_thorns(attacker_id, target)
```

加方法：

```gdscript
# 荆棘：被命中后对攻击者反弹固定伤害（取最高激活档；可致死，不发 attack_executed）。
func _apply_thorns(attacker_id: int, target: UnitInstance) -> void:
	var dmg := 0
	for t in [9, 6, 3]:
		if SetBonus.is_tier_active(target, "set_thorns", t):
			dmg = int(THORNS_DMG[t])
			break
	if dmg > 0:
		_battle_resolution.apply_reaction_damage(attacker_id, dmg)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/set_reactions/set_reaction_thorns_test.gd`
Expected: PASS (3/3)。

- [ ] **Step 5: 提交**

```bash
git add src/battle/set_reaction_system.gd tests/unit/set_reactions/set_reaction_thorns_test.gd
git commit -m "feat(battle): thorns set (reflect 1/2/3, anti-recursion)

Story: set-bonus-effects-reactions
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 处决套（斩杀）

**Files:**
- Modify: `src/battle/set_reaction_system.gd`
- Test: `tests/unit/set_reactions/set_reaction_executioner_test.gd` (create)

**Interfaces:**
- Consumes: 框架 + `apply_reaction_damage`。
- Produces: 私有 `_apply_executioner`；`on_attack_executed` 攻击者侧加处决；常量 `EXECUTIONER`（Dictionary {3:{"thr":3,"dmg":3},6:{"thr":5,"dmg":5},9:{"thr":7,"dmg":7}}）。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/set_reactions/set_reaction_executioner_test.gd`（fixture 同 Task 3）：

```gdscript
# 处决套：命中后目标存活且 hp≤阈值 → 追加斩杀（3/5/7）；hp>阈值不触发。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _srs: SetReactionSystem
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new(); _srs = SetReactionSystem.new()
	add_child(_tm); add_child(_br); add_child(_srs)
	_br.setup(_gb, _tm); _srs.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _srs.free(); _gb.free()

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition: return d
	return null

func _register_set(set_short: String, k: int) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), eq))

func _register_plain() -> int:
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), {}))

func test_executioner_3_finishes_low_hp() -> void:
	var aid := _register_set("executioner", 3)
	var tid := _register_plain()
	var t := _tm.get_unit(tid); t.current_hp = 3   # ≤阈值3
	_srs.on_attack_executed(aid, tid, 1)
	assert_int(t.current_hp).is_equal(0)            # 追加3致死
	assert_bool(t.is_alive).is_false()

func test_executioner_3_skips_high_hp() -> void:
	var aid := _register_set("executioner", 3)
	var tid := _register_plain()
	var t := _tm.get_unit(tid); t.current_hp = 4   # >阈值3
	_srs.on_attack_executed(aid, tid, 1)
	assert_int(t.current_hp).is_equal(4)            # 不触发

func test_executioner_9_threshold_seven() -> void:
	var aid := _register_set("executioner", 9)
	var tid := _register_plain()
	var t := _tm.get_unit(tid); t.current_hp = 7   # ≤阈值7
	_srs.on_attack_executed(aid, tid, 1)
	assert_int(t.current_hp).is_equal(0)            # 追加7致死
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/set_reactions/set_reaction_executioner_test.gd`
Expected: FAIL（无处决分支 → 目标 hp 不变）。

- [ ] **Step 3: 实现**

`set_reaction_system.gd` 常量区加：

```gdscript
const EXECUTIONER := {3: {"thr": 3, "dmg": 3}, 6: {"thr": 5, "dmg": 5}, 9: {"thr": 7, "dmg": 7}}
```

`on_attack_executed` 攻击者侧（嗜血分支旁）加：

```gdscript
		if SetBonus.count_sets(attacker).has("set_executioner"):
			_apply_executioner(attacker, target_id)
```
（注：需 target 在攻击者分支内可用——把 `var target := _turn_manager.get_unit(target_id)` 提到方法开头，攻击者/目标分支共用。）

加方法：

```gdscript
# 处决：命中后若目标存活且 hp≤阈值 → 追加斩杀（取最高激活档；可致死）。
func _apply_executioner(attacker: UnitInstance, target_id: int) -> void:
	var t := _turn_manager.get_unit(target_id)
	if t == null or not t.is_alive:
		return
	for tier in [9, 6, 3]:
		if SetBonus.is_tier_active(attacker, "set_executioner", tier):
			var spec: Dictionary = EXECUTIONER[tier]
			if t.current_hp <= int(spec["thr"]):
				_battle_resolution.apply_reaction_damage(target_id, int(spec["dmg"]))
			return
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/set_reactions/set_reaction_executioner_test.gd`
Expected: PASS (3/3)。

- [ ] **Step 5: 提交**

```bash
git add src/battle/set_reaction_system.gd tests/unit/set_reactions/set_reaction_executioner_test.gd
git commit -m "feat(battle): executioner set (finish low-hp targets)

Story: set-bonus-effects-reactions
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: SetEffectCatalog 扩三套描述

**Files:**
- Modify: `src/ui/set_effect_catalog.gd`
- Test: `tests/unit/set_effects/set_effect_catalog_reactions_test.gd` (create)

**Interfaces:**
- Produces: `SetEffectCatalog._DESC` 补 set_bloodthirst / set_thorns / set_executioner 各 {3,6,9}。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/set_effects/set_effect_catalog_reactions_test.gd`：

```gdscript
# SetEffectCatalog：三反应套各档有中文描述。
extends GdUnitTestSuite

func test_reaction_sets_have_descriptions() -> void:
	for sid in ["set_bloodthirst", "set_thorns", "set_executioner"]:
		for tier in [3, 6, 9]:
			assert_str(SetEffectCatalog.describe(sid, tier)).is_not_equal("")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/set_effects/set_effect_catalog_reactions_test.gd`
Expected: FAIL（三套描述为 ""）。

- [ ] **Step 3: 实现**

`set_effect_catalog.gd` 的 `_DESC` 字典加三键：

```gdscript
	"set_bloodthirst": {3: "吸血¼", 6: "吸血½", 9: "吸血½·外溢"},
	"set_thorns": {3: "反伤1", 6: "反伤2", 9: "反伤3"},
	"set_executioner": {3: "斩杀残血≤3", 6: "斩杀残血≤5", 9: "斩杀残血≤7"},
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/set_effects/set_effect_catalog_reactions_test.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add src/ui/set_effect_catalog.gd tests/unit/set_effects/set_effect_catalog_reactions_test.gd
git commit -m "feat(ui): catalog descriptions for reaction sets

Story: set-bonus-effects-reactions
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 端到端集成 + 全量回归

**Files:**
- Test: `tests/integration/set_reactions/set_reactions_e2e_test.gd` (create)

**Interfaces:**
- Consumes: 全链（execute_attack 真信号 → SetReactionSystem）。

- [ ] **Step 1: 写端到端测试**

创建 `tests/integration/set_reactions/set_reactions_e2e_test.gd`：

```gdscript
# 端到端：真实 execute_attack 触发 attack_executed → SetReactionSystem 反应；阵营无关；防递归。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _srs: SetReactionSystem
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new(); _srs = SetReactionSystem.new()
	add_child(_tm); add_child(_br); add_child(_srs)
	_br.setup(_gb, _tm); _srs.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _srs.free(); _gb.free()

func _def(is_crew: bool, dmg: int) -> UnitDefinition:
	# 取一个对应阵营 def 副本式：直接构造最小 def 保证 base_damage/range 可控。
	var d := UnitDefinition.new()
	d.id = "x"; d.faction = "crew" if is_crew else "enemy"
	d.unit_class = "swordsman"; d.base_damage = dmg; d.move_range = 1; d.attack_range = 1; d.max_hp = 20
	return d

func _register_set(faction_def: UnitDefinition, set_short: String, k: int, pos: Vector2i) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var ed := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[ed.slot] = ed
	var u := UnitInstance.from_definition(faction_def, eq)
	var id := _tm.register_unit(u); u.grid_position = pos; _gb.place_unit(id, pos)
	return id

func test_execute_attack_triggers_bloodthirst_for_enemy_attacker() -> void:
	# 阵营无关：敌方攻击者持嗜血，真打后回血。
	var aid := _register_set(_def(false, 6), "bloodthirst", 6, Vector2i(0, 0))
	var crew_target := UnitInstance.from_definition(_def(true, 0))
	var tid := _tm.register_unit(crew_target); crew_target.grid_position = Vector2i(1, 0); _gb.place_unit(tid, Vector2i(1, 0))
	var a := _tm.get_unit(aid); a.current_hp = 1
	_br.execute_attack(aid, tid)   # 真信号链
	assert_int(a.current_hp).is_greater(1)   # 嗜血回血

func test_attack_into_thorns_reflects_without_recursion() -> void:
	var aid := _register_set(_def(true, 6), "", 0, Vector2i(0, 0))   # 无装备攻击者
	var tdef := _def(false, 0)
	var tid := _register_set(tdef, "thorns", 3, Vector2i(1, 0))
	var a := _tm.get_unit(aid); a.current_hp = 10
	_br.execute_attack(aid, tid)
	assert_int(a.current_hp).is_equal(9)   # 反伤1，且无递归（若递归会多次扣）
```

- [ ] **Step 2: 跑该测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests/integration/set_reactions/set_reactions_e2e_test.gd`
Expected: PASS (2/2)。

- [ ] **Step 3: 全量回归**

Run: `... -a res://tests`
Expected: 全 PASS，0 errors / 0 failures / 0 orphans。捕获 Overall Summary 行。

- [ ] **Step 4: 提交**

```bash
git add tests/integration/set_reactions/set_reactions_e2e_test.gd
git commit -m "test(set): reaction sets e2e (execute_attack-driven, faction-agnostic, anti-recursion) + full regression

Story: set-bonus-effects-reactions
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage：**
- §3.1 触发模型（SetReactionSystem 订阅 attack_executed，看攻击者/目标）→ Task 2 框架 + Task 3/4 分支。✅
- §3.2 防递归（apply_reaction_damage 不发 attack_executed）→ Task 1 + Task 3/4/6 断言。✅
- §3.3 三套阶梯 → Task 2（嗜血）/3（荆棘）/4（处决）。✅
- §3.4 纸娃娃描述 → Task 5。✅
- §3.5 装配 → Task 2 Step 5。✅
- §5 边界（防递归/反伤致死/处决 is_alive/嗜血钳血/斩多目标/多套并存/damage==0）→ Task 1/3/4 实现 + 测试覆盖（多目标/damage0 由 e2e/单测部分覆盖；多套并存逻辑独立分支天然安全）。✅
- §8 AC-1..7 → Task2(AC1)/3(AC2)/4(AC3)/1,3(AC4)/6(AC5)/5(AC6)/6(AC7)。✅
- §9 非目标：未碰寒霜/难度/敌方配装/_compute_attack_damage/美术。✅

**Placeholder 扫描：** 无 TBD/TODO。

**类型一致性：** `apply_reaction_damage(target_id, amount)`（Task1 定义，Task3/4 消费）一致；`SetReactionSystem.setup/on_attack_executed`（Task2 定义，Task3/4/6 复用）一致；常量 BLOODTHIRST_DIV_*/THORNS_DMG/EXECUTIONER；`SetEffectCatalog.describe`（②b-2a 既有，Task5 扩数据）。set_id 字符串统一。

**风险备注（执行者注意）：**
- Task 4 把 `var target` 提到 on_attack_executed 开头供攻击者/目标分支共用——注意改 Task 2/3 已写的取 target 行，避免重复声明。
- 反应在 execute_attack 的 attack_executed 同步回调里运行（步骤 8），其后 execute_attack 还有步骤 9-11；荆棘致死攻击者后 execute_attack 的 mark_has_acted 对已 Downed 单位安全（仅置 flag）。e2e 测试覆盖此路径。
- 测试 GridBoard 未入树须 free（0 孤儿）。
- 数值（嗜血/荆棘/处决）为自主拟定，spec §10 + 本节标注，待 playtest/用户校。
