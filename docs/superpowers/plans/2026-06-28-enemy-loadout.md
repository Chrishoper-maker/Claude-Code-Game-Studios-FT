# 敌方招牌套配装 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给敌方按原型招牌套（守卫铁壁/近战嗜血/突进荆棘/远程处决）+ island_tier 定件数（1/2/3→0/3/6）配装，复用既有装备/套装引擎让高 tier 地图敌人更强。

**Architecture:** 新增纯数据助手 `EnemyLoadout`（静态方法，无状态）把 (behavior_type, island_tier) 映射成 `{slot:int → EquipmentDefinition}`；`BattleMap` 敌方部署的 `from_definition` 调用点接入它。SetEffectSystem/SetReactionSystem 阵营无关且已订阅，敌方套装自动触发，战斗/AI/解算零改动。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。

**Spec:** `docs/superpowers/specs/2026-06-28-enemy-loadout-design.md`

## Global Constraints

- 引擎 Godot 4.6.3；用 API 前查 `docs/engine-reference/`，不臆测后切版本签名。
- 静态类型：所有变量/参数/返回值显式标注（项目惯例）。
- 测试命名 `test_[scenario]_[expected]`；Arrange/Act/Assert 结构；确定性、无随机/无时序断言。
- 常量 UPPER_SNAKE_CASE；类 PascalCase；文件 snake_case。
- 数据驱动：映射/件数为常量表，不硬编码散落。
- 招牌套映射：`{"GUARDIAN":"set_ironwall","MELEE":"set_bloodthirst","SWARMER":"set_thorns","RANGED":"set_executioner"}`，未知类型→空。
- tier→件数：`{1:0, 2:3, 3:6}`，tier≥4→9，tier≤0→0。
- slot 顺序：`["mainweapon","offweapon","head","armor","gloves","legs","boots","ring","necklace"]`；装备 id 格式 `eq_<set_short>_<slotname>`（set_short = set_id 去掉 `set_` 前缀）。
- 敌方招牌套**不含寒霜**（玩家无寒霜结算入口）。
- island_tier 1（及所有现有 tier1 图）必须零回归——敌方 equipment 仍为空。
- 提交用 Conventional Commits，body 含 `Story: enemy-loadout` 与 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 跑测试：`/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 后 `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`。单套件 `-a res://tests/unit/<file>.gd`。

---

### Task 1: EnemyLoadout 纯助手

**Files:**
- Create: `src/data/enemy_loadout.gd`
- Test: `tests/unit/enemy_loadout/enemy_loadout_test.gd`（新建）

**Interfaces:**
- Produces: `EnemyLoadout.for_enemy(behavior_type: String, island_tier: int) -> Dictionary`（返回 `{slot:int → EquipmentDefinition}`，招牌套前 N 件；未知类型/tier≤1 → 空 Dictionary）。

- [ ] **Step 1: 写失败测试**

新建 `tests/unit/enemy_loadout/enemy_loadout_test.gd`：

```gdscript
# EnemyLoadout：原型→招牌套 + island_tier→件数（1/2/3→0/3/6），返回 {slot:int → EquipmentDefinition}。
extends GdUnitTestSuite

func _set_ids(lo: Dictionary) -> Array:
	var out: Array = []
	for k in lo:
		out.append((lo[k] as EquipmentDefinition).set_id)
	return out

func test_guardian_tier2_returns_ironwall_3() -> void:
	var lo := EnemyLoadout.for_enemy("GUARDIAN", 2)
	assert_int(lo.size()).is_equal(3)
	for sid in _set_ids(lo):
		assert_str(sid).is_equal("set_ironwall")

func test_melee_tier3_returns_bloodthirst_6() -> void:
	var lo := EnemyLoadout.for_enemy("MELEE", 3)
	assert_int(lo.size()).is_equal(6)
	for sid in _set_ids(lo):
		assert_str(sid).is_equal("set_bloodthirst")

func test_swarmer_tier2_returns_thorns_3() -> void:
	var lo := EnemyLoadout.for_enemy("SWARMER", 2)
	assert_int(lo.size()).is_equal(3)
	for sid in _set_ids(lo):
		assert_str(sid).is_equal("set_thorns")

func test_ranged_tier3_returns_executioner_6() -> void:
	var lo := EnemyLoadout.for_enemy("RANGED", 3)
	assert_int(lo.size()).is_equal(6)
	for sid in _set_ids(lo):
		assert_str(sid).is_equal("set_executioner")

func test_tier1_returns_empty() -> void:
	assert_int(EnemyLoadout.for_enemy("GUARDIAN", 1).size()).is_equal(0)

func test_unknown_type_returns_empty() -> void:
	assert_int(EnemyLoadout.for_enemy("BOSS", 3).size()).is_equal(0)

func test_keys_are_equipment_slot_ints() -> void:
	var lo := EnemyLoadout.for_enemy("GUARDIAN", 2)
	for k in lo:
		assert_int(int(k)).is_equal((lo[k] as EquipmentDefinition).slot)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/enemy_loadout/enemy_loadout_test.gd`
Expected: FAIL — `EnemyLoadout` 类不存在（解析错误）。

- [ ] **Step 3: 实现 EnemyLoadout**

新建 `src/data/enemy_loadout.gd`：

```gdscript
# 敌方招牌套配装助手（enemy-loadout）：纯静态，无状态。
# 原型 behavior_type → 招牌套 set_id；地图 island_tier → 件数 N（取该套前 N 个 slot）。
# 复用既有装备/套装引擎：返回的 {slot:int → EquipmentDefinition} 直接喂 UnitInstance.from_definition。
class_name EnemyLoadout
extends RefCounted

# 原型 → 阵营无关招牌套（避开寒霜：玩家无寒霜结算入口）。
const ARCHETYPE_SET := {
	"GUARDIAN": "set_ironwall",
	"MELEE": "set_bloodthirst",
	"SWARMER": "set_thorns",
	"RANGED": "set_executioner",
}

# island_tier → 件数（1/2/3→0/3/6；≥4→9；≤0→0）。
const TIER_PIECES := {1: 0, 2: 3, 3: 6}

# 取件 slot 顺序（对应 eq_<set>_<slotname>，EquipmentDefinition.slot 枚举 0..8 同序）。
const SLOT_NAMES := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

# 招牌套前 N 件 → {slot:int → EquipmentDefinition}。未知原型 / N≤0 → 空。
static func for_enemy(behavior_type: String, island_tier: int) -> Dictionary:
	var out: Dictionary = {}
	var set_id: String = ARCHETYPE_SET.get(behavior_type, "")
	if set_id == "":
		return out
	var n := _pieces_for_tier(island_tier)
	if n <= 0:
		return out
	var set_short := set_id.trim_prefix("set_")
	for i in range(mini(n, SLOT_NAMES.size())):
		var eid := "eq_%s_%s" % [set_short, SLOT_NAMES[i]]
		var def := EquipmentDataManager.get_equipment(eid)
		if def != null:
			out[def.slot] = def
	return out

static func _pieces_for_tier(island_tier: int) -> int:
	if TIER_PIECES.has(island_tier):
		return int(TIER_PIECES[island_tier])
	return 9 if island_tier >= 4 else 0
```

- [ ] **Step 4: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/enemy_loadout/enemy_loadout_test.gd`
Expected: PASS（7/7）。

- [ ] **Step 5: 提交**

```bash
git add src/data/enemy_loadout.gd tests/unit/enemy_loadout/enemy_loadout_test.gd tests/unit/enemy_loadout/enemy_loadout_test.gd.uid
git commit -m "feat(data): EnemyLoadout signature-set helper

Story: enemy-loadout

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
（`.uid` 旁车由 `--import` 生成；若不存在则省略该路径。）

---

### Task 2: BattleMap 敌方部署接入 loadout

**Files:**
- Modify: `src/battle/battle_map.gd`（`load_map_definition` 敌方部署循环，`from_definition` 调用点）
- Test: `tests/unit/battle_map/battle_map_enemy_loadout_test.gd`（新建）

**Interfaces:**
- Consumes: `EnemyLoadout.for_enemy(behavior_type, island_tier)`（Task 1）、`SetBonus.is_tier_active(unit, set_id, threshold)`（既有）。

- [ ] **Step 1: 写失败测试**

新建 `tests/unit/battle_map/battle_map_enemy_loadout_test.gd`：

```gdscript
# BattleMap 部署：敌方按 island_tier 获招牌套；tier1 仍零装备（回归）。
extends GdUnitTestSuite

func _bm() -> BattleMap: return auto_free(BattleMap.new())
func _gb() -> GridBoard: return auto_free(GridBoard.new())
func _tm() -> TurnManager: return auto_free(TurnManager.new())

func _cell(pos: Vector2i) -> TerrainCell:
	var c := TerrainCell.new(); c.pos = pos; c.type = "BLOCKED"; return c

func _slot(id: String, pos: Vector2i, behavior: String, home := Vector2i(-1, -1)) -> EnemySlotDefinition:
	var s := EnemySlotDefinition.new()
	s.unit_definition_id = id; s.grid_position = pos; s.behavior_type = behavior; s.home_pos = home
	return s

func _lookup() -> Callable:
	return func(id: String) -> UnitDefinition:
		var d := EnemyDefinition.new()
		d.id = id; d.faction = "enemy"; d.max_hp = 8; d.threat_tier = 1
		return d

# 单守卫地图（GUARDIAN），island_tier 可调；满足 Rule3 最简编制（≥1 敌、无碰撞、部署区充足）。
func _guardian_map(tier: int) -> MapDefinition:
	var m := MapDefinition.new()
	m.map_id = "lo_test"; m.island_tier = tier
	m.terrain_data = []
	var dz: Array[Vector2i] = []
	for x in range(0, 6):
		dz.append(Vector2i(x, 6)); dz.append(Vector2i(x, 7))
	m.deploy_zone = dz
	m.enemy_roster = [_slot("e_guard", Vector2i(7, 3), "GUARDIAN", Vector2i(7, 3))]
	return m

func _first_enemy(tm: TurnManager) -> UnitInstance:
	return tm.get_unit(tm.get_alive_enemies()[0])

func test_tier2_guardian_gets_ironwall_3() -> void:
	var bm := _bm(); var tm := _tm()
	assert_bool(bm.load_map_definition(_guardian_map(2), _gb(), tm, _lookup())).is_true()
	var e := _first_enemy(tm)
	assert_int(e.equipment.size()).is_equal(3)
	assert_bool(SetBonus.is_tier_active(e, "set_ironwall", 3)).is_true()

func test_tier3_guardian_gets_ironwall_6() -> void:
	var bm := _bm(); var tm := _tm()
	assert_bool(bm.load_map_definition(_guardian_map(3), _gb(), tm, _lookup())).is_true()
	var e := _first_enemy(tm)
	assert_int(e.equipment.size()).is_equal(6)
	assert_bool(SetBonus.is_tier_active(e, "set_ironwall", 6)).is_true()

func test_tier1_guardian_has_no_equipment() -> void:
	var bm := _bm(); var tm := _tm()
	assert_bool(bm.load_map_definition(_guardian_map(1), _gb(), tm, _lookup())).is_true()
	assert_int(_first_enemy(tm).equipment.size()).is_equal(0)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_map/battle_map_enemy_loadout_test.gd`
Expected: FAIL — tier2/tier3 敌方 equipment 为空（部署未接 loadout，`is_tier_active` 为 false）。tier1 测试此时即通过。

- [ ] **Step 3: 接入 loadout**

`src/battle/battle_map.gd`，把 `load_map_definition` 敌方部署循环里的 `from_definition` 调用改为带 loadout：

找到：

```gdscript
	for slot in map_def.enemy_roster:
		var def: UnitDefinition = lookup.call(slot.unit_definition_id)
		var inst := UnitInstance.from_definition(def)
```

改为：

```gdscript
	for slot in map_def.enemy_roster:
		var def: UnitDefinition = lookup.call(slot.unit_definition_id)
		var loadout := EnemyLoadout.for_enemy(slot.behavior_type, map_def.island_tier)
		var inst := UnitInstance.from_definition(def, loadout)
```

（其余行 `inst.behavior_type = slot.behavior_type` 等不变。）

- [ ] **Step 4: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_map/battle_map_enemy_loadout_test.gd`
Expected: PASS（3/3）。

- [ ] **Step 5: 跑既有 battle_map + 集成回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_map/battle_map_deploy_test.gd -a res://tests/integration/battle`
Expected: PASS（既有部署/集成零回归——现有图均 island_tier 1/2/3，tier1 图敌方仍零装备；tier2/3 图敌方加套装不破坏部署/胜负流程断言）。

- [ ] **Step 6: 提交**

```bash
git add src/battle/battle_map.gd tests/unit/battle_map/battle_map_enemy_loadout_test.gd tests/unit/battle_map/battle_map_enemy_loadout_test.gd.uid
git commit -m "feat(battle): enemy deploy applies signature-set loadout by tier

Story: enemy-loadout

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 全量回归 + 可见性验收清单

**Files:** 无新增（验证 + 文档）。

- [ ] **Step 1: 全量测试**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
Expected: 全绿（既有 509 + 本批新增 ~10），零失败/错误/孤儿。

- [ ] **Step 2: 记录可见性验收清单（ADVISORY，留 F5 人眼）**

- AC-7：进入 island_tier 2/3 海图，敌人触发套装效果——打荆棘敌（SWARMER）弹反伤飘字、嗜血敌（MELEE）命中弹回血飘字、守卫（GUARDIAN）减伤更难击杀。

- [ ] **Step 3: 无新增代码则跳过提交**（仅验证步）。

---

## Self-Review

**Spec 覆盖**：
- §3.1 EnemyLoadout 助手 → Task 1 ✓；§3.4 BattleMap 接入 → Task 2 ✓。
- §3.2 招牌套映射 → Task 1 ARCHETYPE_SET ✓。
- §3.3 tier→件数 + slot 顺序 → Task 1 TIER_PIECES/SLOT_NAMES ✓。
- §8 AC-1/2/3 → Task 1 测试 ✓；AC-4/5 → Task 2 测试 ✓；AC-6 全量 → Task 3 ✓；AC-7 可见性 → Task 3 清单 ✓。
- §5 边界：tier1 空（Task1 test_tier1 + Task2 test_tier1_guardian_has_no_equipment）✓；未知类型空（Task1 test_unknown_type）✓；装备缺失 null 跳过（for_enemy 内 `if def != null`）✓；crew 不受影响（仅敌方部署路径调用 EnemyLoadout）✓；寒霜不含（ARCHETYPE_SET 无 set_frost）✓。

**占位符扫描**：无 TBD/TODO；每个代码步均含完整代码与确切命令/预期。

**类型一致性**：`EnemyLoadout.for_enemy(behavior_type: String, island_tier: int) -> Dictionary` 在 Task 1 定义、Task 2 调用一致；返回 `{slot:int → EquipmentDefinition}` 键即 `def.slot`（Task1 test_keys_are_equipment_slot_ints 锁定），Task2 断言 `equipment.size()` 与 `SetBonus.is_tier_active` 一致；set_id 字面量（set_ironwall/bloodthirst/thorns/executioner）跨 spec/plan/测试一致。
