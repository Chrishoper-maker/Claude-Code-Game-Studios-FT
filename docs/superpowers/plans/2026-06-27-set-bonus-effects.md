# 套装效果引擎 + 四基础套（②b-2a）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让套装产生战斗加成——搭建阵营无关的套装效果引擎，落地铁壁/狂战/医者/航海四套的 3/6/9 效果（每回合开始施加），并在纸娃娃显示效果描述。

**Architecture:** 新纯函数 `SetBonus`（从 `UnitInstance.equipment` 算套装件数/档位）+ 新 `SetEffectSystem` 节点（订阅 `round_started`，遍历全体存活单位按档位施加效果，复用 BattleResolution 的 status/heal）。BattleResolution 加 3 个 round-status（FRENZY/FRENZY_PERSIST/SET_GUARD）并把 `clear_round_statuses` 接到 `round_ended`。纸娃娃用 `SetEffectCatalog` 追加效果文字。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。战斗系统节点（GridBoard/TurnManager/BattleResolution/各 effect 节点）+ EventBus。

## Global Constraints

- 引擎 Godot 4.6.3；测试 GdUnit4：先 `/Applications/Godot.app/Contents/MacOS/Godot --headless --import`，再 `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a <test path>`。
- 命名：类 PascalCase、变量/函数 snake_case、信号过去式 snake_case、常量 UPPER_SNAKE_CASE。
- GDScript 静态类型；公共 API 写中文 doc 注释。
- 数值数据驱动：效果数值用具名常量（不散落魔法数）。
- autoload 脚本不声明 class_name；数据/运行时/战斗系统类声明 class_name。
- 提交用 Conventional Commits，body 引用 `Story: set-bonus-effects`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 8 套 set_id（②b-1）：set_ironwall/set_berserker/set_healer/set_navigator/set_bloodthirst/set_thorns/set_executioner/set_frost。本期只实现前四套效果。
- 套装阈值 [3,6,9]，累加语义（count≥阈值即激活）；升级型档位取最高变体，新增型档位叠加。
- 效果**阵营无关**：对任何持装备+档位激活的存活单位生效（不限 crew）。
- 攻击增益仅作用于普通攻击与斩（slash）；炮击不受影响。

## File Structure

- `src/battle/set_bonus.gd`（建）：纯静态 helper，从 UnitInstance 算套装件数/档位。
- `src/battle/set_effect_system.gd`（建）：Node，订阅 round_started，施加四套效果。
- `src/battle/battle_resolution.gd`（改）：加 3 round-status + 攻击增益取高/persist 不消耗 + set_guard 减半不消耗 + clear_round_statuses 扩展并接 round_ended。
- `src/ui/set_effect_catalog.gd`（建）：纯静态，(set_id, tier) → 中文效果描述。
- `src/ui/route_scene.gd`（改）：纸娃娃套装行追加效果描述。
- `scenes/BattleScene.tscn` + `src/battle/battle_scene.gd`（改）：加 SetEffectSystem 节点 + 装配。
- 测试：`tests/unit/set_bonus/`、`tests/unit/battle_resolution/`（扩展）、`tests/unit/set_effects/`、`tests/integration/set_effects/`。

---

### Task 1: SetBonus 纯档位 helper

**Files:**
- Create: `src/battle/set_bonus.gd`
- Test: `tests/unit/set_bonus/set_bonus_test.gd` (create)

**Interfaces:**
- Produces:
  - `SetBonus.count_sets(unit: UnitInstance) -> Dictionary`（{set_id:String → count:int}，仅含 count≥1 且 set_id 非空）
  - `SetBonus.is_tier_active(unit: UnitInstance, set_id: String, threshold: int) -> bool`（count≥threshold）

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/set_bonus/set_bonus_test.gd`：

```gdscript
# SetBonus：从 UnitInstance.equipment 算套装件数/档位（累加语义）。
extends GdUnitTestSuite

# 用 K 件某套装备造一个 crew UnitInstance（取该套前 K 个槽）。
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition:
			return d
	return null

func _unit_with(set_short: String, k: int) -> UnitInstance:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	return UnitInstance.from_definition(_crew_def(), eq)

func test_count_sets_groups_by_set_id() -> void:
	var u := _unit_with("ironwall", 5)
	var counts := SetBonus.count_sets(u)
	assert_int(int(counts.get("set_ironwall", 0))).is_equal(5)

func test_count_sets_empty_when_no_equipment() -> void:
	var u := UnitInstance.from_definition(_crew_def(), {})
	assert_int(SetBonus.count_sets(u).size()).is_equal(0)

func test_is_tier_active_cumulative_boundaries() -> void:
	var u := _unit_with("ironwall", 6)
	assert_bool(SetBonus.is_tier_active(u, "set_ironwall", 3)).is_true()
	assert_bool(SetBonus.is_tier_active(u, "set_ironwall", 6)).is_true()
	assert_bool(SetBonus.is_tier_active(u, "set_ironwall", 9)).is_false()

func test_is_tier_active_below_threshold() -> void:
	var u := _unit_with("ironwall", 2)
	assert_bool(SetBonus.is_tier_active(u, "set_ironwall", 3)).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests/unit/set_bonus/set_bonus_test.gd`
Expected: FAIL（SetBonus 未定义）

- [ ] **Step 3: 实现**

创建 `src/battle/set_bonus.gd`：

```gdscript
# 套装档位纯函数 helper（②b-2a）。从 UnitInstance.equipment（{slot:def}）算各套件数/档位。
# 无状态、阵营无关、不依赖 RunManager；供 SetEffectSystem 读取。
class_name SetBonus
extends RefCounted

# 各套持有件数 {set_id → count}（仅含 ≥1；无 set_id 的件不计）。
static func count_sets(unit: UnitInstance) -> Dictionary:
	var counts: Dictionary = {}
	if unit == null:
		return counts
	for slot in unit.equipment:
		var def: EquipmentDefinition = unit.equipment[slot]
		if def != null and def.set_id != "":
			counts[def.set_id] = int(counts.get(def.set_id, 0)) + 1
	return counts

# 某套某档是否激活（累加语义：持有件数 ≥ threshold）。
static func is_tier_active(unit: UnitInstance, set_id: String, threshold: int) -> bool:
	return int(count_sets(unit).get(set_id, 0)) >= threshold
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/set_bonus/set_bonus_test.gd`
Expected: PASS (4/4)

- [ ] **Step 5: 提交**

```bash
git add src/battle/set_bonus.gd tests/unit/set_bonus/set_bonus_test.gd
git commit -m "feat(battle): SetBonus tier helper (counts/is_tier_active)

Story: set-bonus-effects
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: BattleResolution round-status 扩展

**Files:**
- Modify: `src/battle/battle_resolution.gd`
- Test: `tests/unit/battle_resolution/set_status_test.gd` (create)

**Interfaces:**
- Produces:
  - 常量 `STATUS_FRENZY`(&"FRENZY") / `STATUS_FRENZY_PERSIST`(&"FRENZY_PERSIST") / `STATUS_SET_GUARD`(&"SET_GUARD")
  - 攻击增益：FRENZY/FRENZY_PERSIST → +2（取代 AURA +1）；攻击后消耗 FRENZY 与 AURA，不消耗 FRENZY_PERSIST。
  - `_apply_guard` 读 SET_GUARD（减半，不消耗，优先 GUARDED）。
  - `clear_round_statuses` 清除 GUARDED/FRENZY/FRENZY_PERSIST/SET_GUARD；`setup` 把它接到 `round_ended`。
- Consumes: 既有 STATUS_GUARDED/STATUS_AURA/AURA_VALUE/GUARD_DIVISOR。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/battle_resolution/set_status_test.gd`：

```gdscript
# BattleResolution 新 round-status：frenzy 取高/persist 不消耗、set_guard 减半不消耗、round 清除。
extends GdUnitTestSuite

var _br: BattleResolution
var _tm: TurnManager
var _gb: GridBoard

func before_test() -> void:
	_gb = GridBoard.new()
	_tm = TurnManager.new()
	_br = BattleResolution.new()
	add_child(_tm)
	add_child(_br)
	_br.setup(_gb, _tm)

func after_test() -> void:
	_tm.free()
	_br.free()

func _enemy_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is EnemyDefinition:
			return d
	return null

func _register(faction_def: UnitDefinition) -> int:
	var u := UnitInstance.from_definition(faction_def)
	return _tm.register_unit(u)

func test_frenzy_gives_plus_two_and_consumes() -> void:
	var aid := _register(_enemy_def())
	_br.apply_status(aid, BattleResolution.STATUS_FRENZY)
	var a := _tm.get_unit(aid)
	var dmg := _br._compute_attack_damage(aid, a)
	assert_int(dmg).is_equal(a.get_base_damage() + 2)
	# 消耗：第二次无加成
	assert_int(_br._compute_attack_damage(aid, a)).is_equal(a.get_base_damage())

func test_frenzy_persist_not_consumed() -> void:
	var aid := _register(_enemy_def())
	_br.apply_status(aid, BattleResolution.STATUS_FRENZY_PERSIST)
	var a := _tm.get_unit(aid)
	assert_int(_br._compute_attack_damage(aid, a)).is_equal(a.get_base_damage() + 2)
	assert_int(_br._compute_attack_damage(aid, a)).is_equal(a.get_base_damage() + 2)

func test_frenzy_takes_priority_over_aura() -> void:
	var aid := _register(_enemy_def())
	_br.apply_status(aid, BattleResolution.STATUS_AURA)
	_br.apply_status(aid, BattleResolution.STATUS_FRENZY)
	var a := _tm.get_unit(aid)
	assert_int(_br._compute_attack_damage(aid, a)).is_equal(a.get_base_damage() + 2)

func test_set_guard_halves_without_consume() -> void:
	var tid := _register(_enemy_def())
	_br.apply_status(tid, BattleResolution.STATUS_SET_GUARD)
	assert_int(_br._apply_guard(tid, 10)).is_equal(5)
	assert_int(_br._apply_guard(tid, 8)).is_equal(4)   # 未消耗，仍减半

func test_clear_round_statuses_clears_new() -> void:
	var id := _register(_enemy_def())
	_br.apply_status(id, BattleResolution.STATUS_FRENZY_PERSIST)
	_br.apply_status(id, BattleResolution.STATUS_SET_GUARD)
	_br.clear_round_statuses()
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FRENZY_PERSIST)).is_false()
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_SET_GUARD)).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/battle_resolution/set_status_test.gd`
Expected: FAIL（STATUS_FRENZY 未定义）

- [ ] **Step 3: 实现**

在 `battle_resolution.gd` 常量区（STATUS_AURA 之后）加：

```gdscript
const STATUS_FRENZY := &"FRENZY"               # 套装攻击增益 +2（攻击后消耗）
const STATUS_FRENZY_PERSIST := &"FRENZY_PERSIST"  # 套装攻击增益 +2（本轮不消耗）
const STATUS_SET_GUARD := &"SET_GUARD"         # 套装减半（本轮不消耗）
const FRENZY_VALUE := 2                         # 狂热增益
```

在 `setup` 末尾加 round_ended 接线（启用 round-status 按轮清除，修复既有未接线）：

```gdscript
	if not EventBus.round_ended.is_connected(clear_round_statuses):
		EventBus.round_ended.connect(clear_round_statuses)
```

加峰值/消耗 helper（放在 _compute_attack_damage 前）：

```gdscript
# 攻击增益（不消耗，仅查询）：FRENZY/PERSIST→+2 取代 AURA→+1。
func _peek_attack_bonus(attacker_id: int) -> int:
	if get_unit_status(attacker_id, STATUS_FRENZY) or get_unit_status(attacker_id, STATUS_FRENZY_PERSIST):
		return FRENZY_VALUE
	if get_unit_status(attacker_id, STATUS_AURA):
		return AURA_VALUE
	return 0

# 攻击后消耗一次性增益（FRENZY + AURA；PERSIST 不消耗）。
func _consume_attack_bonus(attacker_id: int) -> void:
	_consume_status(attacker_id, STATUS_FRENZY)
	_consume_status(attacker_id, STATUS_AURA)
```

把 `_compute_attack_damage` 改为：

```gdscript
func _compute_attack_damage(attacker_id: int, a: UnitInstance) -> int:
	var modifier_sum := mini(_pending_modifiers.get(attacker_id, 0), MAX_MODIFIER_SUM)
	var bonus := _peek_attack_bonus(attacker_id)
	_consume_attack_bonus(attacker_id)
	return a.get_base_damage() + modifier_sum + bonus
```

把 `execute_slash` 内 aura 段改为用 helper。原：

```gdscript
	var has_aura := get_unit_status(attacker_id, STATUS_AURA)
	var aura := AURA_VALUE if has_aura else 0
```
改为：
```gdscript
	var aura := _peek_attack_bonus(attacker_id)
```
并把原步骤 ⑧ 的：
```gdscript
	if has_aura:                                      # ⑧
		_consume_status(attacker_id, STATUS_AURA)
```
改为：
```gdscript
	_consume_attack_bonus(attacker_id)               # ⑧
```
（slash 内 `pre_guard = a.get_base_damage() + modifier_sum + aura` 不变；变量名 aura 现承载取高后的增益。）

把 `_apply_guard` 改为：

```gdscript
func _apply_guard(target_id: int, dmg: int) -> int:
	if get_unit_status(target_id, STATUS_SET_GUARD):
		return dmg / GUARD_DIVISOR            # 套装减半，不消耗
	if get_unit_status(target_id, STATUS_GUARDED):
		_consume_status(target_id, STATUS_GUARDED)
		return dmg / GUARD_DIVISOR
	return dmg
```

把 `clear_round_statuses` 改为：

```gdscript
func clear_round_statuses() -> void:
	for id in _unit_statuses:
		_unit_statuses[id].erase(STATUS_GUARDED)
		_unit_statuses[id].erase(STATUS_FRENZY)
		_unit_statuses[id].erase(STATUS_FRENZY_PERSIST)
		_unit_statuses[id].erase(STATUS_SET_GUARD)
```

- [ ] **Step 4: 跑测试确认通过 + 全量回归**

Run: `... -a res://tests/unit/battle_resolution/set_status_test.gd`
Expected: PASS (5/5)
然后全量：`... -a res://tests`
Expected: 0 失败/错误/孤儿。⚠️ 接线 clear_round_statuses 到 round_ended 是行为变更（此前从未清除）——若有既有测试因 GUARDED 现在按轮清除而红，说明它依赖旧的"GUARDED 跨轮残留"，需评估：多数情形 GUARDED 受击即消耗，应不受影响。若红，定位并在报告中说明。

- [ ] **Step 5: 提交**

```bash
git add src/battle/battle_resolution.gd tests/unit/battle_resolution/set_status_test.gd
git commit -m "feat(battle): frenzy/set-guard round-statuses + wire clear_round_statuses to round_ended

Story: set-bonus-effects
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: SetEffectSystem 框架 + 铁壁 + 战斗装配

**Files:**
- Create: `src/battle/set_effect_system.gd`
- Modify: `scenes/BattleScene.tscn`, `src/battle/battle_scene.gd`
- Test: `tests/unit/set_effects/set_effect_ironwall_test.gd` (create)

**Interfaces:**
- Consumes: `SetBonus`（Task 1）、BattleResolution 的 `apply_status`/`execute_burst_heal`/新 status（Task 2）、TurnManager `get_alive_allies/get_alive_enemies/get_unit`、`EventBus.round_started`。
- Produces:
  - `SetEffectSystem.setup(grid_board: GridBoard, turn_manager: TurnManager, battle_resolution: BattleResolution) -> void`
  - `SetEffectSystem.on_round_started(round_count: int) -> void`
  - `SetEffectSystem.IRONWALL_HEAL`(=3)
  - 私有 `_apply_ironwall`、`_all_alive_ids`、`_same_faction_within_ids`

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/set_effects/set_effect_ironwall_test.gd`：

```gdscript
# 铁壁套：round_started 后 3件得 GUARDED、6件+3自愈、9件得 SET_GUARD。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _ses: SetEffectSystem

const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new()
	_tm = TurnManager.new()
	_br = BattleResolution.new()
	_ses = SetEffectSystem.new()
	add_child(_tm); add_child(_br); add_child(_ses)
	_br.setup(_gb, _tm)
	_ses.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _ses.free()

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition:
			return d
	return null

func _register_with(set_short: String, k: int, pos: Vector2i) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	var u := UnitInstance.from_definition(_crew_def(), eq)
	var id := _tm.register_unit(u)
	u.grid_position = pos
	return id

func test_ironwall_3_grants_guarded() -> void:
	var id := _register_with("ironwall", 3, Vector2i(0, 0))
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_GUARDED)).is_true()

func test_ironwall_6_heals_three() -> void:
	var id := _register_with("ironwall", 6, Vector2i(0, 0))
	var u := _tm.get_unit(id)
	u.current_hp = 1
	_ses.on_round_started(1)
	assert_int(u.current_hp).is_equal(mini(1 + SetEffectSystem.IRONWALL_HEAL, u.get_max_hp()))

func test_ironwall_9_grants_set_guard() -> void:
	var id := _register_with("ironwall", 9, Vector2i(0, 0))
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_SET_GUARD)).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/set_effects/set_effect_ironwall_test.gd`
Expected: FAIL（SetEffectSystem 未定义）

- [ ] **Step 3: 实现 SetEffectSystem（框架 + 铁壁）**

创建 `src/battle/set_effect_system.gd`：

```gdscript
# 套装效果引擎（②b-2a）。订阅 round_started，每轮起对全体存活单位按套装档位施加效果。
# 阵营无关（对任何持装备+档位激活的存活单位生效）。复用 BattleResolution status/heal。
class_name SetEffectSystem
extends Node

const IRONWALL_HEAL := 3
const HEALER_HEAL := 3
const HEALER_HEAL_HIGH := 6
const NAVIGATOR_RADIUS := 1
const NAVIGATOR_RADIUS_HIGH := 2

var _grid_board: GridBoard
var _turn_manager: TurnManager
var _battle_resolution: BattleResolution

func setup(grid_board: GridBoard, turn_manager: TurnManager, battle_resolution: BattleResolution) -> void:
	_grid_board = grid_board
	_turn_manager = turn_manager
	_battle_resolution = battle_resolution
	if not EventBus.round_started.is_connected(on_round_started):
		EventBus.round_started.connect(on_round_started)

# 每轮起：遍历全体存活单位，按其激活套装施加效果。
func on_round_started(_round_count: int) -> void:
	for uid in _all_alive_ids():
		var unit := _turn_manager.get_unit(uid)
		if unit == null or not unit.is_alive:
			continue
		for sid in SetBonus.count_sets(unit):
			match sid:
				"set_ironwall": _apply_ironwall(uid, unit)
				_: pass

# 铁壁：3=GUARDED（升级轴），9=SET_GUARD（取代 GUARDED）；6=+3自愈（新增轴）。
func _apply_ironwall(uid: int, unit: UnitInstance) -> void:
	if SetBonus.is_tier_active(unit, "set_ironwall", 9):
		_battle_resolution.apply_status(uid, BattleResolution.STATUS_SET_GUARD)
	elif SetBonus.is_tier_active(unit, "set_ironwall", 3):
		_battle_resolution.apply_status(uid, BattleResolution.STATUS_GUARDED)
	if SetBonus.is_tier_active(unit, "set_ironwall", 6):
		_battle_resolution.execute_burst_heal(uid, IRONWALL_HEAL)

# 全体存活 battle_id（两阵营）。
func _all_alive_ids() -> Array[int]:
	var ids: Array[int] = _turn_manager.get_alive_allies()
	ids.append_array(_turn_manager.get_alive_enemies())
	return ids

# 与 source 同阵营、存活、非自身、切比雪夫 ≤radius 的单位 battle_id。
func _same_faction_within_ids(source: UnitInstance, radius: int) -> Array[int]:
	var out: Array[int] = []
	for id in _all_alive_ids():
		var u := _turn_manager.get_unit(id)
		if u != null and u != source and u.is_alive \
				and u.definition.faction == source.definition.faction \
				and GridBoard.chebyshev(source.grid_position, u.grid_position) <= radius:
			out.append(id)
	return out
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/set_effects/set_effect_ironwall_test.gd`
Expected: PASS (3/3)

- [ ] **Step 5: 战斗装配**

`scenes/BattleScene.tscn`：在节点树加一个 `SetEffectSystem` 节点（脚本 `res://src/battle/set_effect_system.gd`），与 AdjacencyBond/BondGaugeBurst 同级（Node3D 根的直接子节点）。参考既有 BondGaugeBurst 节点的 .tscn 写法（ext_resource 脚本 + node 段）。

`src/battle/battle_scene.gd`：加 `@onready var _set_effect_system: SetEffectSystem = $SetEffectSystem`（与其它 @onready 同处），并在 `_ready` 的装配段（BondGaugeBurst.setup 之后）加：

```gdscript
	_set_effect_system.setup(_grid_board, _turn_manager, _battle_resolution)
```

- [ ] **Step 6: 导入 + 全量回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests`
Expected: 0 失败/错误/孤儿（含既有 battle 集成测试，SetEffectSystem 节点存在且 setup 成功）。

- [ ] **Step 7: 提交**

```bash
git add src/battle/set_effect_system.gd scenes/BattleScene.tscn src/battle/battle_scene.gd tests/unit/set_effects/set_effect_ironwall_test.gd
git commit -m "feat(battle): SetEffectSystem framework + ironwall set + wiring

Story: set-bonus-effects
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 狂战套效果

**Files:**
- Modify: `src/battle/set_effect_system.gd`
- Test: `tests/unit/set_effects/set_effect_berserker_test.gd` (create)

**Interfaces:**
- Consumes: SetEffectSystem 框架（Task 3）、BattleResolution STATUS_AURA/FRENZY/FRENZY_PERSIST（Task 2）。
- Produces: 私有 `_apply_berserker`；`on_round_started` 的 match 加 `"set_berserker"` 分支。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/set_effects/set_effect_berserker_test.gd`（复用 Task 3 测试的 before_test/_register_with 结构）：

```gdscript
# 狂战套：3=AURA / 6=FRENZY(取代AURA) / 9=FRENZY_PERSIST。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _ses: SetEffectSystem
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new(); _ses = SetEffectSystem.new()
	add_child(_tm); add_child(_br); add_child(_ses)
	_br.setup(_gb, _tm); _ses.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _ses.free()

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition: return d
	return null

func _register_with(set_short: String, k: int) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), eq))

func test_berserker_3_grants_aura() -> void:
	var id := _register_with("berserker", 3)
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_AURA)).is_true()
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FRENZY)).is_false()

func test_berserker_6_grants_frenzy_not_aura() -> void:
	var id := _register_with("berserker", 6)
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FRENZY)).is_true()
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_AURA)).is_false()

func test_berserker_9_grants_frenzy_persist() -> void:
	var id := _register_with("berserker", 9)
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FRENZY_PERSIST)).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/set_effects/set_effect_berserker_test.gd`
Expected: FAIL（无 berserker 分支 → status 全 false）

- [ ] **Step 3: 实现**

`on_round_started` 的 match 加分支：

```gdscript
				"set_berserker": _apply_berserker(uid, unit)
```

加方法：

```gdscript
# 狂战：升级轴取最高——9=持续狂热 / 6=狂热 / 3=光环。
func _apply_berserker(uid: int, unit: UnitInstance) -> void:
	if SetBonus.is_tier_active(unit, "set_berserker", 9):
		_battle_resolution.apply_status(uid, BattleResolution.STATUS_FRENZY_PERSIST)
	elif SetBonus.is_tier_active(unit, "set_berserker", 6):
		_battle_resolution.apply_status(uid, BattleResolution.STATUS_FRENZY)
	elif SetBonus.is_tier_active(unit, "set_berserker", 3):
		_battle_resolution.apply_status(uid, BattleResolution.STATUS_AURA)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/set_effects/set_effect_berserker_test.gd`
Expected: PASS (3/3)

- [ ] **Step 5: 提交**

```bash
git add src/battle/set_effect_system.gd tests/unit/set_effects/set_effect_berserker_test.gd
git commit -m "feat(battle): berserker set effect (aura/frenzy/persist)

Story: set-bonus-effects
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 医者套效果

**Files:**
- Modify: `src/battle/set_effect_system.gd`
- Test: `tests/unit/set_effects/set_effect_healer_test.gd` (create)

**Interfaces:**
- Consumes: 框架 + `execute_burst_heal` + `_same_faction_within_ids`。
- Produces: 私有 `_apply_healer`；match 加 `"set_healer"` 分支。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/set_effects/set_effect_healer_test.gd`（结构同上，_register_with 带 pos）：

```gdscript
# 医者套：3=自身+3 / 6=相邻友军也+3 / 9=翻倍+6。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _ses: SetEffectSystem
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new(); _ses = SetEffectSystem.new()
	add_child(_tm); add_child(_br); add_child(_ses)
	_br.setup(_gb, _tm); _ses.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _ses.free()

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition: return d
	return null

func _register_with(set_short: String, k: int, pos: Vector2i) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	var u := UnitInstance.from_definition(_crew_def(), eq)
	var id := _tm.register_unit(u)
	u.grid_position = pos
	return id

func _register_plain(pos: Vector2i) -> int:
	var u := UnitInstance.from_definition(_crew_def(), {})
	var id := _tm.register_unit(u)
	u.grid_position = pos
	return id

func test_healer_3_heals_self() -> void:
	var id := _register_with("healer", 3, Vector2i(0, 0))
	var u := _tm.get_unit(id); u.current_hp = 1
	_ses.on_round_started(1)
	assert_int(u.current_hp).is_equal(mini(1 + SetEffectSystem.HEALER_HEAL, u.get_max_hp()))

func test_healer_6_heals_adjacent_ally() -> void:
	var hid := _register_with("healer", 6, Vector2i(0, 0))
	var aid := _register_plain(Vector2i(1, 0))   # 相邻
	var ally := _tm.get_unit(aid); ally.current_hp = 1
	_ses.on_round_started(1)
	assert_int(ally.current_hp).is_equal(mini(1 + SetEffectSystem.HEALER_HEAL, ally.get_max_hp()))

func test_healer_9_doubles_amount() -> void:
	var id := _register_with("healer", 9, Vector2i(0, 0))
	var u := _tm.get_unit(id); u.current_hp = 1
	_ses.on_round_started(1)
	assert_int(u.current_hp).is_equal(mini(1 + SetEffectSystem.HEALER_HEAL_HIGH, u.get_max_hp()))
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/set_effects/set_effect_healer_test.gd`
Expected: FAIL

- [ ] **Step 3: 实现**

match 加分支：

```gdscript
				"set_healer": _apply_healer(uid, unit)
```

加方法：

```gdscript
# 医者：自愈量 9=6 否则=3（升级轴）；相邻友军在 6 档起也回（新增轴）。
func _apply_healer(uid: int, unit: UnitInstance) -> void:
	var amount := HEALER_HEAL_HIGH if SetBonus.is_tier_active(unit, "set_healer", 9) else HEALER_HEAL
	_battle_resolution.execute_burst_heal(uid, amount)
	if SetBonus.is_tier_active(unit, "set_healer", 6):
		for ally_id in _same_faction_within_ids(unit, NAVIGATOR_RADIUS):
			_battle_resolution.execute_burst_heal(ally_id, amount)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/set_effects/set_effect_healer_test.gd`
Expected: PASS (3/3)

- [ ] **Step 5: 提交**

```bash
git add src/battle/set_effect_system.gd tests/unit/set_effects/set_effect_healer_test.gd
git commit -m "feat(battle): healer set effect (self/adjacent heal, double at 9)

Story: set-bonus-effects
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 航海套效果

**Files:**
- Modify: `src/battle/set_effect_system.gd`
- Test: `tests/unit/set_effects/set_effect_navigator_test.gd` (create)

**Interfaces:**
- Consumes: 框架 + `apply_status` + `_same_faction_within_ids`。
- Produces: 私有 `_apply_navigator`；match 加 `"set_navigator"` 分支。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/set_effects/set_effect_navigator_test.gd`（结构同 Task 5，含 _register_with(pos)/_register_plain(pos)）：

```gdscript
# 航海套：3=相邻友军AURA / 6=相邻友军也GUARDED / 9=半径扩到2格。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _ses: SetEffectSystem
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new(); _ses = SetEffectSystem.new()
	add_child(_tm); add_child(_br); add_child(_ses)
	_br.setup(_gb, _tm); _ses.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _ses.free()

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition: return d
	return null

func _register_with(set_short: String, k: int, pos: Vector2i) -> int:
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

func test_navigator_3_buffs_adjacent_aura() -> void:
	_register_with("navigator", 3, Vector2i(0, 0))
	var aid := _register_plain(Vector2i(1, 0))
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(aid, BattleResolution.STATUS_AURA)).is_true()

func test_navigator_6_buffs_adjacent_guarded() -> void:
	_register_with("navigator", 6, Vector2i(0, 0))
	var aid := _register_plain(Vector2i(1, 0))
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(aid, BattleResolution.STATUS_GUARDED)).is_true()

func test_navigator_9_extends_radius_to_two() -> void:
	_register_with("navigator", 9, Vector2i(0, 0))
	var near := _register_plain(Vector2i(2, 0))   # 切比雪夫=2
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(near, BattleResolution.STATUS_AURA)).is_true()

func test_navigator_3_does_not_reach_two() -> void:
	_register_with("navigator", 3, Vector2i(0, 0))
	var far := _register_plain(Vector2i(2, 0))   # 半径1够不到
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(far, BattleResolution.STATUS_AURA)).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/set_effects/set_effect_navigator_test.gd`
Expected: FAIL

- [ ] **Step 3: 实现**

match 加分支：

```gdscript
				"set_navigator": _apply_navigator(uid, unit)
```

加方法：

```gdscript
# 航海：半径 9=2 否则=1（升级轴）；相邻友军得 AURA，6 档起也得 GUARDED（新增轴）。
func _apply_navigator(_uid: int, unit: UnitInstance) -> void:
	var radius := NAVIGATOR_RADIUS_HIGH if SetBonus.is_tier_active(unit, "set_navigator", 9) else NAVIGATOR_RADIUS
	var also_guard := SetBonus.is_tier_active(unit, "set_navigator", 6)
	for ally_id in _same_faction_within_ids(unit, radius):
		_battle_resolution.apply_status(ally_id, BattleResolution.STATUS_AURA)
		if also_guard:
			_battle_resolution.apply_status(ally_id, BattleResolution.STATUS_GUARDED)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/set_effects/set_effect_navigator_test.gd`
Expected: PASS (4/4)

- [ ] **Step 5: 提交**

```bash
git add src/battle/set_effect_system.gd tests/unit/set_effects/set_effect_navigator_test.gd
git commit -m "feat(battle): navigator set effect (team aura/guard, radius 2 at 9)

Story: set-bonus-effects
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: SetEffectCatalog + 纸娃娃效果标记

**Files:**
- Create: `src/ui/set_effect_catalog.gd`
- Modify: `src/ui/route_scene.gd`
- Test: `tests/unit/set_effects/set_effect_catalog_test.gd` (create)

**Interfaces:**
- Produces: `SetEffectCatalog.describe(set_id: String, tier: int) -> String`（四基础套各档中文描述；未知套/档返回 ""）。
- Consumes（route_scene）：`RunManager.get_set_counts`/`get_active_set_tier`（②b-1 既有，纸娃娃用）。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/set_effects/set_effect_catalog_test.gd`：

```gdscript
# SetEffectCatalog：(set_id,tier) → 中文效果描述。
extends GdUnitTestSuite

func test_describe_known_set_tier_nonempty() -> void:
	assert_str(SetEffectCatalog.describe("set_ironwall", 9)).is_not_equal("")
	assert_str(SetEffectCatalog.describe("set_berserker", 3)).is_not_equal("")
	assert_str(SetEffectCatalog.describe("set_healer", 6)).is_not_equal("")
	assert_str(SetEffectCatalog.describe("set_navigator", 9)).is_not_equal("")

func test_describe_unknown_returns_empty() -> void:
	assert_str(SetEffectCatalog.describe("set_frost", 3)).is_equal("")
	assert_str(SetEffectCatalog.describe("set_ironwall", 1)).is_equal("")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/set_effects/set_effect_catalog_test.gd`
Expected: FAIL（SetEffectCatalog 未定义）

- [ ] **Step 3: 实现 catalog**

创建 `src/ui/set_effect_catalog.gd`：

```gdscript
# 套装效果中文描述表（②b-2a，纸娃娃用）。仅四基础套；未知套/档返回 ""。
class_name SetEffectCatalog
extends RefCounted

const _DESC := {
	"set_ironwall": {3: "首击减半", 6: "+3自愈", 9: "钢铁壁垒·全轮减半"},
	"set_berserker": {3: "攻击+1", 6: "狂热·攻击+2", 9: "持续狂热·每击+2"},
	"set_healer": {3: "自愈+3", 6: "相邻友军+3", 9: "治疗翻倍+6"},
	"set_navigator": {3: "邻友攻击+1", 6: "邻友首击减半", 9: "增益半径+1"},
}

# 某套某档效果描述；未知套或非 {3,6,9} 档返回 ""。
static func describe(set_id: String, tier: int) -> String:
	var by_tier: Variant = _DESC.get(set_id, null)
	if by_tier is Dictionary:
		return str((by_tier as Dictionary).get(tier, ""))
	return ""
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/set_effects/set_effect_catalog_test.gd`
Expected: PASS (2/2)

- [ ] **Step 5: 纸娃娃追加描述**

`src/ui/route_scene.gd` 的 `_build_paperdoll`，套装行循环（当前为 `for sid in counts:` 内构造 `head.text`）。把 head.text 构造改为追加激活档描述：在设置 `head.text` 之后加（tier>0 时）累计描述：

```gdscript
		var tier := RunManager.get_active_set_tier(crew_id, str(sid))
		var head := Label.new()
		var line := "%s %d/9%s" % [str(sid), int(counts[sid]), "（已激活 %d）" % tier if tier > 0 else ""]
		if tier > 0:
			var descs: Array[String] = []
			for t in [3, 6, 9]:
				if int(counts[sid]) >= t:
					var d := SetEffectCatalog.describe(str(sid), t)
					if d != "":
						descs.append(d)
			if not descs.is_empty():
				line += " ✦" + " / ".join(descs)
		head.text = line
		v.add_child(head)
```
（替换原先直接 `head.text = "%s %d/9%s" % [...]` + `v.add_child(head)` 两行；保持其余纸娃娃逻辑不变。）

- [ ] **Step 6: 导入 + 全量回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests`
Expected: 0 失败/错误/孤儿（纸娃娃既有交互测试仍绿）。

- [ ] **Step 7: 提交**

```bash
git add src/ui/set_effect_catalog.gd src/ui/route_scene.gd tests/unit/set_effects/set_effect_catalog_test.gd
git commit -m "feat(ui): set-effect catalog + paper-doll effect markers

Story: set-bonus-effects
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: 端到端集成 + 全量回归

**Files:**
- Test: `tests/integration/set_effects/set_effects_e2e_test.gd` (create)

**Interfaces:**
- Consumes: 全链（GridBoard + TurnManager + BattleResolution + SetEffectSystem，经 round_started 真实信号驱动）。

- [ ] **Step 1: 写端到端测试**

创建 `tests/integration/set_effects/set_effects_e2e_test.gd`：

```gdscript
# 端到端：真实 round_started 信号驱动 SetEffectSystem，铁壁9件单位本轮多次受击均减半；
# 阵营无关——enemy faction 带装备也生效（AC-6）。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _ses: SetEffectSystem
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new(); _ses = SetEffectSystem.new()
	add_child(_tm); add_child(_br); add_child(_ses)
	_br.setup(_gb, _tm); _ses.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _ses.free()

func _def(is_crew: bool) -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if is_crew and d is CrewDefinition: return d
		if not is_crew and d is EnemyDefinition: return d
	return null

func _register_set(is_crew: bool, set_short: String, k: int) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	return _tm.register_unit(UnitInstance.from_definition(_def(is_crew), eq))

func test_round_started_signal_drives_set_guard() -> void:
	var id := _register_set(true, "ironwall", 9)
	EventBus.round_started.emit(1)   # 真实信号
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_SET_GUARD)).is_true()
	# 本轮多次受击均减半（set_guard 不消耗）
	assert_int(_br._apply_guard(id, 10)).is_equal(5)
	assert_int(_br._apply_guard(id, 6)).is_equal(3)

func test_effect_is_faction_agnostic_for_enemy() -> void:
	var eid := _register_set(false, "berserker", 6)   # 敌方带狂战6
	EventBus.round_started.emit(1)
	assert_bool(_br.get_unit_status(eid, BattleResolution.STATUS_FRENZY)).is_true()
```

- [ ] **Step 2: 跑该测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests/integration/set_effects/set_effects_e2e_test.gd`
Expected: PASS (2/2)

- [ ] **Step 3: 全量回归**

Run: `... -a res://tests`
Expected: 全 PASS，0 errors / 0 failures / 0 orphans。捕获 Overall Summary 行。若红，定位修复（多为 round_ended 清除 GUARDED 的行为变更影响既有测试）。

- [ ] **Step 4: 提交**

```bash
git add tests/integration/set_effects/set_effects_e2e_test.gd
git commit -m "test(set): set-effects e2e (round_started-driven, faction-agnostic) + full regression

Story: set-bonus-effects
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage：**
- §3.1 档位语义（累加/升级取最高/新增叠加）→ Task 1（SetBonus）+ 各 set 任务的分发逻辑。✅
- §3.2 施加时机（round_started 遍历全体存活）→ Task 3 on_round_started。✅
- §3.3 四套效果 → Task 3(铁壁)/4(狂战)/5(医者)/6(航海)。✅
- §3.4 BattleResolution 扩展（3 status + frenzy 取高/persist 不消耗 + set_guard + clear 接 round_ended + 炮击不受影响）→ Task 2。✅（炮击不受影响=未改 execute_cannon，天然满足。）
- §3.5 纸娃娃效果标记 → Task 7。✅
- §5 边界（无装备跳过/混搭独立/set_guard 主导/钳 max/Downed 跳过/persist 本轮/航海空范围）→ Task 3-6 实现 + 测试覆盖（混搭未单列测试，但各套独立 match 分支天然独立；e2e 覆盖阵营无关）。✅
- §8 AC-1..9 → Task1(AC1)/3(AC2)/4(AC3)/5(AC4)/6(AC5)/8(AC6)/2(AC7)/7(AC8)/8(AC9)。✅
- §9 非目标：未碰嗜血/荆棘/处决/寒霜/难度/敌方配装/HUD 实时图标。✅

**Placeholder 扫描：** 无 TBD/TODO。catalog 对非四基础套返回 "" 是设计（非占位）。

**类型一致性：** `SetBonus.count_sets/is_tier_active`（Task1 定义，Task3-6 消费）签名一致；`SetEffectSystem.setup/on_round_started/_same_faction_within_ids/常量`（Task3 定义，Task4-6 复用）一致；`BattleResolution.STATUS_FRENZY/FRENZY_PERSIST/SET_GUARD`（Task2 定义，Task3-6/8 引用）一致；`SetEffectCatalog.describe`（Task7）一致。set_id 字符串字面量（"set_ironwall" 等）全计划统一。

**风险备注（执行者注意）：**
- Task 2 把 `clear_round_statuses` 接到 `round_ended` 是**行为变更**（此前从未清除）。GUARDED 此前靠受击消耗，未受击则跨轮残留；接线后按轮清。跑全量验证；若既有测试红，说明依赖旧残留行为，需在报告说明并评估（预期不受影响——GUARDED 正常受击即消耗）。
- `_compute_attack_damage`/`_apply_guard` 是 `_` 前缀私有方法但测试直接调用——项目既有测试模式（battle_resolution_test 已如此），可接受。
- 各 set 测试构造 UnitInstance 带 equipment 依赖 ②b-1 的 72 件数据（eq_<set>_<slotkey> 命名）；已合并 main，可用。
