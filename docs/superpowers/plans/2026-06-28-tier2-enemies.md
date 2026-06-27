# tier2 敌方原型 + 升级 island_tier3 图 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 4 个 tier2 敌方原型（更高血/攻），把 island_tier3 地图（006/007）的敌人升级为 tier2，让 run 末岛成为硬仗。

**Architecture:** 纯数据增量，零新代码逻辑。新增 4 个 `EnemyDefinition` `.tres`（threat_tier=2，沿用 tier1 的 unit_class/behavior_type）；UnitDataManager 自动扫描；改 006/007 的 enemy_roster 引用为 tier2；BattleMap 验证 F5 允许 [1,2] 故通过；EnemyLoadout 按 behavior_type+island_tier3 仍给 6 件套。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4 / .tres Resource。

**Spec:** `docs/superpowers/specs/2026-06-28-tier2-enemies-design.md`

## Global Constraints

- 引擎 Godot 4.6.3；用 API 前查 `docs/engine-reference/`。
- 静态类型：测试中所有变量/参数/返回值显式标注。
- 测试命名 `test_[scenario]_[expected]`；Arrange/Act/Assert；确定性。
- tier2 数值（spec §3.2，逐字）：
  - `enemy_melee_tier2`：近战兵·精锐 / swordsman / MELEE / hp9 / dmg4 / range1 / move2 / threat_tier2
  - `enemy_ranged_tier2`：炮击兵·精锐 / gunner / RANGED / hp8 / dmg4 / range3 / move2 / threat_tier2
  - `enemy_swarmer_tier2`：群攻兵·精锐 / swordsman / SWARMER / hp6 / dmg3 / range1 / move3 / threat_tier2
  - `enemy_guardian_tier2`：守卫兵·精锐 / bulwark / GUARDIAN / hp12 / dmg3 / range1 / move1 / threat_tier2
- `.tres` 结构照搬对应 tier1（`assets/data/units/enemy_<arch>_tier1.tres`）：同 ext_resource 脚本、faction="enemy"、class_action_id=""、home_pos=Vector2i(-1,-1)。
- 006/007 仅改 enemy_roster 的 `unit_definition_id`（tier1→tier2）；grid_position/behavior_type/home_pos/数量不变；001-005 不动。
- 提交 Conventional Commits，body 含 `Story: tier2-enemies` 与 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 跑测试：`/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 后 `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`。单套件 `-a res://tests/unit/<file>.gd`。

---

### Task 1: 4 个 tier2 敌方 .tres

**Files:**
- Create: `assets/data/units/enemy_melee_tier2.tres`、`enemy_ranged_tier2.tres`、`enemy_swarmer_tier2.tres`、`enemy_guardian_tier2.tres`
- Test: `tests/unit/enemy_tier2/enemy_tier2_test.gd`（新建）

**Interfaces:**
- Produces: `UnitDataManager.get_unit("enemy_<arch>_tier2") -> EnemyDefinition`（4 个新原型，字段见 Global Constraints）。Task 2 的地图引用它们。

- [ ] **Step 1: 写失败测试**

新建 `tests/unit/enemy_tier2/enemy_tier2_test.gd`：

```gdscript
# tier2 敌方原型数据校验：经 UnitDataManager 取得、类型/字段正确（spec §3.2）。
extends GdUnitTestSuite

func _enemy(id: String) -> EnemyDefinition:
	return UnitDataManager.get_unit(id) as EnemyDefinition

func test_melee_tier2_fields() -> void:
	var e := _enemy("enemy_melee_tier2")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(2)
	assert_int(e.max_hp).is_equal(9)
	assert_int(e.base_damage).is_equal(4)
	assert_int(e.attack_range).is_equal(1)
	assert_int(e.move_range).is_equal(2)
	assert_str(e.unit_class).is_equal("swordsman")
	assert_str(e.behavior_type).is_equal("MELEE")

func test_ranged_tier2_fields() -> void:
	var e := _enemy("enemy_ranged_tier2")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(2)
	assert_int(e.max_hp).is_equal(8)
	assert_int(e.base_damage).is_equal(4)
	assert_int(e.attack_range).is_equal(3)
	assert_int(e.move_range).is_equal(2)
	assert_str(e.unit_class).is_equal("gunner")
	assert_str(e.behavior_type).is_equal("RANGED")

func test_swarmer_tier2_fields() -> void:
	var e := _enemy("enemy_swarmer_tier2")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(2)
	assert_int(e.max_hp).is_equal(6)
	assert_int(e.base_damage).is_equal(3)
	assert_int(e.attack_range).is_equal(1)
	assert_int(e.move_range).is_equal(3)
	assert_str(e.unit_class).is_equal("swordsman")
	assert_str(e.behavior_type).is_equal("SWARMER")

func test_guardian_tier2_fields() -> void:
	var e := _enemy("enemy_guardian_tier2")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(2)
	assert_int(e.max_hp).is_equal(12)
	assert_int(e.base_damage).is_equal(3)
	assert_int(e.attack_range).is_equal(1)
	assert_int(e.move_range).is_equal(1)
	assert_str(e.unit_class).is_equal("bulwark")
	assert_str(e.behavior_type).is_equal("GUARDIAN")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/enemy_tier2/enemy_tier2_test.gd`
Expected: FAIL — 4 原型 `get_unit` 返 null（.tres 不存在）。

- [ ] **Step 3: 创建 4 个 .tres**

`assets/data/units/enemy_melee_tier2.tres`：

```
[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/enemy_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "enemy_melee_tier2"
display_name = "近战兵·精锐"
faction = "enemy"
unit_class = "swordsman"
max_hp = 9
move_range = 2
attack_range = 1
base_damage = 4
class_action_id = ""
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)
threat_tier = 2
```

`assets/data/units/enemy_ranged_tier2.tres`：

```
[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/enemy_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "enemy_ranged_tier2"
display_name = "炮击兵·精锐"
faction = "enemy"
unit_class = "gunner"
max_hp = 8
move_range = 2
attack_range = 3
base_damage = 4
class_action_id = ""
behavior_type = "RANGED"
home_pos = Vector2i(-1, -1)
threat_tier = 2
```

`assets/data/units/enemy_swarmer_tier2.tres`：

```
[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/enemy_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "enemy_swarmer_tier2"
display_name = "群攻兵·精锐"
faction = "enemy"
unit_class = "swordsman"
max_hp = 6
move_range = 3
attack_range = 1
base_damage = 3
class_action_id = ""
behavior_type = "SWARMER"
home_pos = Vector2i(-1, -1)
threat_tier = 2
```

`assets/data/units/enemy_guardian_tier2.tres`：

```
[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/enemy_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "enemy_guardian_tier2"
display_name = "守卫兵·精锐"
faction = "enemy"
unit_class = "bulwark"
max_hp = 12
move_range = 1
attack_range = 1
base_damage = 3
class_action_id = ""
behavior_type = "GUARDIAN"
home_pos = Vector2i(-1, -1)
threat_tier = 2
```

- [ ] **Step 4: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/enemy_tier2/enemy_tier2_test.gd`
Expected: PASS（4/4）。

- [ ] **Step 5: 提交**

```bash
git add assets/data/units/enemy_melee_tier2.tres assets/data/units/enemy_ranged_tier2.tres assets/data/units/enemy_swarmer_tier2.tres assets/data/units/enemy_guardian_tier2.tres tests/unit/enemy_tier2/enemy_tier2_test.gd tests/unit/enemy_tier2/enemy_tier2_test.gd.uid
git commit -m "feat(data): tier2 enemy archetypes

Story: tier2-enemies

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
（`.tres.uid` 若由 `--import` 生成亦一并 add；`.gd.uid` 同。不存在则省略。）

---

### Task 2: 升级 006/007 enemy_roster 为 tier2

**Files:**
- Modify: `assets/data/maps/battle_map_006.tres`、`assets/data/maps/battle_map_007.tres`（enemy_roster 引用）
- Test: `tests/unit/battle_map/battle_map_tier2_maps_test.gd`（新建）

**Interfaces:**
- Consumes: `UnitDataManager.get_unit("enemy_<arch>_tier2")`（Task 1）、`MapDataManager.get_map(id)`、`BattleMap.load_map_definition`、`SetBonus`（既有）。

- [ ] **Step 1: 写失败测试**

新建 `tests/unit/battle_map/battle_map_tier2_maps_test.gd`：

```gdscript
# island_tier3 图(006/007)敌人升级为 tier2：roster 全 tier2、仍过 Rule3、部署后为 tier2+6件套。
extends GdUnitTestSuite

func _deployed_first_enemy(map_id: String) -> UnitInstance:
	var bm: BattleMap = auto_free(BattleMap.new())
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	bm.load_map_definition(MapDataManager.get_map(map_id), gb, tm)
	return tm.get_unit(tm.get_alive_enemies()[0])

func test_map_006_roster_all_tier2() -> void:
	var m := MapDataManager.get_map("battle_map_006") as MapDefinition
	for slot in m.enemy_roster:
		assert_str(slot.unit_definition_id).ends_with("_tier2")

func test_map_007_roster_all_tier2() -> void:
	var m := MapDataManager.get_map("battle_map_007") as MapDefinition
	for slot in m.enemy_roster:
		assert_str(slot.unit_definition_id).ends_with("_tier2")

func test_map_006_passes_rule3() -> void:
	var bm: BattleMap = auto_free(BattleMap.new())
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	assert_bool(bm.load_map_definition(MapDataManager.get_map("battle_map_006"), gb, tm)).is_true()

func test_map_007_passes_rule3() -> void:
	var bm: BattleMap = auto_free(BattleMap.new())
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	assert_bool(bm.load_map_definition(MapDataManager.get_map("battle_map_007"), gb, tm)).is_true()

func test_deployed_006_enemy_is_tier2_with_six_piece_loadout() -> void:
	var e := _deployed_first_enemy("battle_map_006")
	assert_int(e.definition.threat_tier).is_equal(2)
	assert_int(e.equipment.size()).is_equal(6)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_map/battle_map_tier2_maps_test.gd`
Expected: FAIL — roster 仍为 tier1（`ends_with("_tier2")` 失败、threat_tier 为 1）。

- [ ] **Step 3: 改 006 enemy_roster 引用**

`assets/data/maps/battle_map_006.tres`，把 enemy_roster 里的 3 个 tier1 id 全改为 tier2（用 Edit replace_all，逐 id 一次）：

- 将 `unit_definition_id = "enemy_melee_tier1"` 全部替换为 `unit_definition_id = "enemy_melee_tier2"`（2 处）。
- 将 `unit_definition_id = "enemy_ranged_tier1"` 全部替换为 `unit_definition_id = "enemy_ranged_tier2"`（2 处）。
- 将 `unit_definition_id = "enemy_guardian_tier1"` 全部替换为 `unit_definition_id = "enemy_guardian_tier2"`（1 处）。

（grid_position/behavior_type/home_pos/enemy_roster 数组/island_tier 行均不动。）

- [ ] **Step 4: 改 007 enemy_roster 引用**

`assets/data/maps/battle_map_007.tres`，同法替换：

- 将 `unit_definition_id = "enemy_swarmer_tier1"` 全部替换为 `unit_definition_id = "enemy_swarmer_tier2"`（2 处）。
- 将 `unit_definition_id = "enemy_ranged_tier1"` 全部替换为 `unit_definition_id = "enemy_ranged_tier2"`（1 处）。
- 将 `unit_definition_id = "enemy_guardian_tier1"` 全部替换为 `unit_definition_id = "enemy_guardian_tier2"`（2 处）。

- [ ] **Step 5: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_map/battle_map_tier2_maps_test.gd`
Expected: PASS（5/5）。

- [ ] **Step 6: 跑既有多地图回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/maps/map_pool_test.gd`
Expected: PASS（既有逐图 Rule3 + tier 索引仍绿：tier 索引按 island_tier 不变、006/007 仍过 Rule3）。

- [ ] **Step 7: 提交**

```bash
git add assets/data/maps/battle_map_006.tres assets/data/maps/battle_map_007.tres tests/unit/battle_map/battle_map_tier2_maps_test.gd tests/unit/battle_map/battle_map_tier2_maps_test.gd.uid
git commit -m "feat(data): upgrade island_tier3 maps (006/007) to tier2 enemies

Story: tier2-enemies

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 全量回归 + 可见性验收清单

**Files:** 无新增（验证 + 文档）。

- [ ] **Step 1: 全量测试**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import && /Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
Expected: 全绿（既有 519 + 本批新增 ~9），零失败/错误/孤儿。

- [ ] **Step 2: 记录可见性验收清单（ADVISORY，留 F5 人眼）**

- AC-6：F5 走到末岛（island_tier3，006/007），敌人明显更肉更痛（tier2 数值 + 6 件招牌套叠加）。

- [ ] **Step 3: 无新增代码则跳过提交**（仅验证步）。

---

## Self-Review

**Spec 覆盖**：
- §3.1/§3.2 4 个 tier2 原型 → Task 1 ✓。
- §3.3 升级 006/007 → Task 2 ✓。
- §8 AC-1 → Task 1 测试 ✓；AC-2（validate 通过）→ Task 2 test_map_00X_passes_rule3 ✓；AC-3（roster 全 tier2）→ Task 2 test_map_00X_roster_all_tier2 ✓；AC-4（部署 tier2+6 件）→ Task 2 test_deployed_006... ✓；AC-5 全量回归 → Task 3 ✓；AC-6 可见性 → Task 3 清单 ✓。
- §5 边界：004/005 不动（Task 仅碰 006/007）✓；Rule3 不破（Task2 Step6 既有 map_pool 回归）✓；渲染沿用 unit_class（.tres unit_class 同 tier1）✓；招牌套沿用 behavior_type（.tres behavior_type 同 tier1，Task2 部署测试断 equipment.size==6）✓。

**占位符扫描**：无 TBD/TODO；每个文件/编辑步均含完整内容与确切命令/预期。

**类型一致性**：4 个 id（enemy_melee/ranged/swarmer/guardian_tier2）跨 Task1 创建、Task1 测试、Task2 地图引用、Task2 测试一致；数值（hp9/8/6/12、dmg4/4/3/3）与 spec §3.2 一致；threat_tier=2 一致；EnemyLoadout 件数 6（island_tier3）与 Task2 断言一致。
