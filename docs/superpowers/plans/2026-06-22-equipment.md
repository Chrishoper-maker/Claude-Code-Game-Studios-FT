# 装备系统（MVP·纯数值·招募卡携带）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让招募获得的船员携带一件随机装备，纯粹修改 `max_hp/base_damage/attack_range/move_range` 四项数值，绑定到船员、随其存在于本 run、随阵亡/终局消失。

**Architecture:** 新增 `EquipmentDefinition`（Resource）+ `EquipmentDataManager`（autoload 扫描 .tres）。装备加成走**方案 A**：UnitInstance 持 `equipment` 字段并暴露 `get_max_hp/get_base_damage/get_attack_range/get_move_range` 有效值访问器，战斗代码从 `unit.definition.X` 改读 `unit.get_X()`。RunManager 持 `_roster_equipment`/`_offer_equipment` 账本，招募时用 `_rng` 滚装备并入存档。RouteScene 招募卡追加装备标签。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。

## Global Constraints

- 引擎 Godot 4.6.3；测试前必 `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import`；GdUnit4 须加 `--ignoreHeadlessMode`。
- 静态类型纪律：禁 `var x := <Variant 表达式>`；遍历 `Dictionary`/`Array` 元素先显式标注或 `as T`；`Dictionary.get(...)` 结果用 `var x: Variant` + 类型守卫。
- autoload 脚本**不声明 class_name**（注册名即全局单例）；Resource/运行时类**可**带 class_name。
- 持久化：装备账本进 `user://run.json`（复用既有 to_save_dict/load_from_save_dict）；`_offer_equipment` 不存（resume 由 rng_state 复现）。
- 既有驱 RunManager 的测试套件 `before_test` 已设 `_autosave_enabled=false`；新测试沿用。
- 中文对话；标识符英文。trunk-based 在 main。
- 提交 Conventional Commits，body 带 `Story: equipment (#15)`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 装备只作用于 crew；敌方 UnitInstance 的 equipment 恒 null（有效值=基值）。

---

### Task 1: EquipmentDefinition + EquipmentDataManager + 装备池 + autoload 注册

**Files:**
- Create: `src/data/equipment_definition.gd`
- Create: `src/autoloads/equipment_data_manager.gd`
- Create: `assets/data/equipment/eq_cutlass.tres` / `eq_plate.tres` / `eq_spyglass.tres` / `eq_boots.tres`
- Modify: `project.godot`（`[autoload]` 段加 EquipmentDataManager，置于 UnitDataManager 之后、RunManager 之前）
- Test: `tests/unit/equipment/equipment_data_test.gd`

**Interfaces:**
- Produces:
  - `EquipmentDefinition`（Resource，class_name）字段 `id:String / display_name:String / hp_bonus:int / damage_bonus:int / range_bonus:int / move_bonus:int`。
  - `EquipmentDataManager.get_equipment(id:String) -> EquipmentDefinition`（缺失 null）、`get_all_equipment() -> Array[EquipmentDefinition]`、`is_loaded:bool`。

- [ ] **Step 1: 写脚本 EquipmentDefinition**

`src/data/equipment_definition.gd`:

```gdscript
# 装备定义模板（只读静态数据）。纯数值增量，作用于携带它的船员 UnitInstance。
# 运行时不写回；与 UnitDefinition 并列，由 EquipmentDataManager 扫描缓存。
class_name EquipmentDefinition
extends Resource

@export var id: String
@export var display_name: String
@export var hp_bonus: int
@export var damage_bonus: int
@export var range_bonus: int
@export var move_bonus: int
```

- [ ] **Step 2: 写 autoload EquipmentDataManager**

`src/autoloads/equipment_data_manager.gd`（仿 UnitDataManager；不声明 class_name）:

```gdscript
# 装备数据管理器（autoload）。启动扫描 res://assets/data/equipment/ 下全部 .tres，校验后缓存。
# 失败快速：结构错误 → push_error + 清空 → get_all_equipment() 返回 []。
# （autoload 脚本不声明 class_name：注册名 EquipmentDataManager 即全局单例访问）
extends Node

const EQUIPMENT_DATA_PATH := "res://assets/data/equipment/"

var _cache: Dictionary = {}                     # String id → EquipmentDefinition
var _all: Array[EquipmentDefinition] = []
var is_loaded: bool = false

func _ready() -> void:
	_scan_and_load()

func get_equipment(id: String) -> EquipmentDefinition:
	return _cache.get(id, null)

func get_all_equipment() -> Array[EquipmentDefinition]:
	return _all if is_loaded else []

func _scan_and_load() -> void:
	var dir := DirAccess.open(EQUIPMENT_DATA_PATH)
	if dir == null:
		push_error("EquipmentData parse error: %s — 目录无法打开" % EQUIPMENT_DATA_PATH)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var path := EQUIPMENT_DATA_PATH + fname
			var res := ResourceLoader.load(path)
			if res == null:
				push_error("EquipmentData parse error: %s — ResourceLoader 返回 null" % path)
			elif not (res is EquipmentDefinition):
				push_error("EquipmentData parse error: %s — 非 EquipmentDefinition 类型" % path)
			else:
				_all.append(res as EquipmentDefinition)
		fname = dir.get_next()
	_validate_all()

func _validate_all() -> void:
	var seen_ids: Dictionary = {}
	var has_error := false
	for def in _all:
		if def.id in seen_ids:
			push_error("EquipmentData validation error: %s — 重复 id" % def.id)
			has_error = true
		else:
			seen_ids[def.id] = true
	if not has_error:
		for def in _all:
			_cache[def.id] = def
		is_loaded = true
	else:
		_all.clear()
```

- [ ] **Step 3: 写 4 个装备 .tres**

`assets/data/equipment/eq_plate.tres`:

```
[gd_resource type="Resource" script_class="EquipmentDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/equipment_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "eq_plate"
display_name = "板甲"
hp_bonus = 3
damage_bonus = 0
range_bonus = 0
move_bonus = 0
```

`assets/data/equipment/eq_cutlass.tres`（同结构，`id="eq_cutlass"` `display_name="弯刀"` `damage_bonus=1` 其余 0）。
`assets/data/equipment/eq_spyglass.tres`（`id="eq_spyglass"` `display_name="望远镜"` `range_bonus=1` 其余 0）。
`assets/data/equipment/eq_boots.tres`（`id="eq_boots"` `display_name="轻靴"` `move_bonus=1` 其余 0）。

- [ ] **Step 4: 注册 autoload**

`project.godot` `[autoload]` 段，在 `UnitDataManager=...` 行后插入：

```
EquipmentDataManager="*res://src/autoloads/equipment_data_manager.gd"
```

- [ ] **Step 5: 写失败测试**

`tests/unit/equipment/equipment_data_test.gd`:

```gdscript
# EquipmentDataManager 扫描 + 查询（实跑 .tres，仿 definitions_test）。
extends GdUnitTestSuite

# AC-1：扫描后池含 ≥4 件，get_equipment 返回正确增量。
func test_loads_equipment_pool() -> void:
	assert_bool(EquipmentDataManager.is_loaded).is_true()
	assert_int(EquipmentDataManager.get_all_equipment().size()).is_greater_equal(4)
	var plate := EquipmentDataManager.get_equipment("eq_plate")
	assert_bool(plate != null).is_true()
	assert_int(plate.hp_bonus).is_equal(3)
	assert_int(plate.damage_bonus).is_equal(0)

func test_missing_id_returns_null() -> void:
	assert_object(EquipmentDataManager.get_equipment("eq_nonexistent_zzz")).is_null()
```

- [ ] **Step 6: 导入 + 跑测试（先 RED 再 GREEN）**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/equipment/equipment_data_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
```
Expected: 2/2 PASSED（autoload 与 .tres 就绪后）。

- [ ] **Step 7: 提交**

```bash
git add src/data/equipment_definition.gd src/autoloads/equipment_data_manager.gd assets/data/equipment/ project.godot tests/unit/equipment/
git commit -F - <<'EOF'
feat(data): EquipmentDefinition + EquipmentDataManager + starter pool

Story: equipment (#15)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

> 注：本任务新增的 `.gd`/`.tres` 会生成 `.uid` 边车文件，`git add` 目录会一并纳入；提交前 `git status` 确认无遗漏 `.uid`。

---

### Task 2: UnitInstance equipment 字段 + 有效值访问器

**Files:**
- Modify: `src/data/unit_instance.gd`
- Test: `tests/unit/unit_instance_equipment/unit_instance_equipment_test.gd`

**Interfaces:**
- Consumes: `EquipmentDefinition`（Task 1）。
- Produces: `UnitInstance.equipment:EquipmentDefinition`；`from_definition(def, equipment:EquipmentDefinition=null)`；`get_max_hp()/get_base_damage()/get_attack_range()/get_move_range() -> int`。

- [ ] **Step 1: 写失败测试**

`tests/unit/unit_instance_equipment/unit_instance_equipment_test.gd`:

```gdscript
# UnitInstance 有效值（装备增量；无装备=基值；初始 current_hp=有效 max_hp）。
extends GdUnitTestSuite

func _def() -> UnitDefinition:
	var d := UnitDefinition.new()
	d.id = "test_unit"
	d.faction = "crew"
	d.unit_class = "swordsman"
	d.max_hp = 10
	d.base_damage = 3
	d.attack_range = 1
	d.move_range = 3
	d.class_action_id = "slash"
	return d

func _equip(hp: int, dmg: int, rng: int, mv: int) -> EquipmentDefinition:
	var e := EquipmentDefinition.new()
	e.id = "test_eq"
	e.display_name = "测试装备"
	e.hp_bonus = hp
	e.damage_bonus = dmg
	e.range_bonus = rng
	e.move_bonus = mv
	return e

# AC-3：无装备 → 有效值=基值。
func test_no_equipment_returns_base() -> void:
	var inst := UnitInstance.from_definition(_def())
	assert_int(inst.get_max_hp()).is_equal(10)
	assert_int(inst.get_base_damage()).is_equal(3)
	assert_int(inst.get_attack_range()).is_equal(1)
	assert_int(inst.get_move_range()).is_equal(3)
	assert_int(inst.current_hp).is_equal(10)

# AC-2：有装备 → 有效值=基值+增量，初始 current_hp=有效 max_hp。
func test_equipment_adds_bonuses() -> void:
	var inst := UnitInstance.from_definition(_def(), _equip(3, 1, 1, 1))
	assert_int(inst.get_max_hp()).is_equal(13)
	assert_int(inst.get_base_damage()).is_equal(4)
	assert_int(inst.get_attack_range()).is_equal(2)
	assert_int(inst.get_move_range()).is_equal(4)
	assert_int(inst.current_hp).is_equal(13)

# 负增量钳 0（防御）。
func test_negative_bonus_clamped_to_zero() -> void:
	var inst := UnitInstance.from_definition(_def(), _equip(-100, -100, -100, -100))
	assert_int(inst.get_max_hp()).is_equal(0)
	assert_int(inst.get_base_damage()).is_equal(0)
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/unit_instance_equipment/unit_instance_equipment_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -4
```
Expected: 解析/运行错误（get_max_hp 等不存在）。

- [ ] **Step 3: 改 UnitInstance**

在 `src/data/unit_instance.gd`：
① 在字段区（`var home_pos: Vector2i` 之后）加：

```gdscript
var equipment: EquipmentDefinition = null   # 携带装备（仅 crew；敌方/无装备为 null）
```

② 把 `from_definition` 签名与 current_hp 初始化改为：

```gdscript
static func from_definition(def: UnitDefinition, equipment: EquipmentDefinition = null) -> UnitInstance:
	var inst := UnitInstance.new()
	inst.definition = def
	inst.equipment = equipment
	inst.current_hp = inst.get_max_hp()          # 初始 = 有效 max_hp（含装备）
	inst.grid_position = SENTINEL_POS
	inst.has_moved = false
	inst.has_acted = false
	inst.has_used_verb = def.class_action_id == ""
	inst.is_alive = true
	inst.behavior_type = ""
	inst.home_pos = SENTINEL_POS
	return inst
```

③ 在文件末尾（`get_unit_id()` 之后）加四个访问器：

```gdscript
# ── 有效值（基值 + 装备增量，下限钳 0）。战斗逻辑应读这些而非 definition.X ──
func get_max_hp() -> int:
	return maxi(0, definition.max_hp + (equipment.hp_bonus if equipment != null else 0))

func get_base_damage() -> int:
	return maxi(0, definition.base_damage + (equipment.damage_bonus if equipment != null else 0))

func get_attack_range() -> int:
	return maxi(0, definition.attack_range + (equipment.range_bonus if equipment != null else 0))

func get_move_range() -> int:
	return maxi(0, definition.move_range + (equipment.move_bonus if equipment != null else 0))
```

- [ ] **Step 4: 跑测试确认 GREEN**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/unit_instance_equipment/unit_instance_equipment_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
```
Expected: 3/3 PASSED。

- [ ] **Step 5: 提交**

```bash
git add src/data/unit_instance.gd tests/unit/unit_instance_equipment/
git commit -F - <<'EOF'
feat(data): UnitInstance equipment field + effective-stat accessors

Story: equipment (#15)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 3: 战斗读值切换（battle_resolution / player_turn_controller / battle_hud / enemy_ai）

**Files:**
- Modify: `src/battle/battle_resolution.gd`、`src/battle/player_turn_controller.gd`、`src/ui/battle_hud.gd`、`src/ai/enemy_ai.gd`
- Test: 无新增（既有 200+ 测试为回归网；无装备时有效值=基值，行为不变）。

**Interfaces:**
- Consumes: `UnitInstance.get_max_hp/get_base_damage/get_attack_range/get_move_range()`（Task 2）。

> **机械替换**：这四个文件里所有对 UnitInstance 的 `.definition.max_hp / .definition.base_damage / .definition.attack_range / .definition.move_range` 读取，改为对应 `.get_max_hp() / .get_base_damage() / .get_attack_range() / .get_move_range()`。变量前缀不同（a./t./u.）不影响——替换的是 `.definition.<stat>` 片段。**注意**：`battle_scene.gd` 的同类读取留给 Task 5（与部署接线一起改），本任务不碰它。

- [ ] **Step 1: 替换 battle_resolution.gd**

对 `src/battle/battle_resolution.gd` 执行 4 次全局替换：
- `.definition.base_damage` → `.get_base_damage()`
- `.definition.attack_range` → `.get_attack_range()`
- `.definition.max_hp` → `.get_max_hp()`
- （该文件无 `.definition.move_range`，跳过）

（涉及行：约 70/99/146/170/226/228/248/258/267/288，替换后无 `.definition.{base_damage,attack_range,max_hp}` 残留。）

- [ ] **Step 2: 替换 player_turn_controller.gd**

对 `src/battle/player_turn_controller.gd` 执行：
- `.definition.move_range` → `.get_move_range()`
- `.definition.attack_range` → `.get_attack_range()`

- [ ] **Step 3: 替换 battle_hud.gd**

对 `src/ui/battle_hud.gd`：
- `.definition.max_hp` → `.get_max_hp()`

- [ ] **Step 4: 替换 enemy_ai.gd**

对 `src/ai/enemy_ai.gd`：
- `.definition.move_range` → `.get_move_range()`
- `.definition.attack_range` → `.get_attack_range()`

- [ ] **Step 5: 确认无残留**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
grep -nE "\.definition\.(max_hp|base_damage|attack_range|move_range)" src/battle/battle_resolution.gd src/battle/player_turn_controller.gd src/ui/battle_hud.gd src/ai/enemy_ai.gd
```
Expected: 无输出（四文件已全部切换；`battle_scene.gd` 不在此列，留 Task 5）。

- [ ] **Step 6: 全量回归确认行为不变**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: 全量绿、0 失败/错误（无装备时有效值=基值，回归无回退）。

- [ ] **Step 7: 提交**

```bash
git add src/battle/battle_resolution.gd src/battle/player_turn_controller.gd src/ui/battle_hud.gd src/ai/enemy_ai.gd
git commit -F - <<'EOF'
refactor(battle): read effective stats via UnitInstance.get_* accessors

Story: equipment (#15)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 4: RunManager 装备账本（滚装备 / 记账 / 查询 / permadeath 擦除）

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_equipment/run_equipment_test.gd`

**Interfaces:**
- Consumes: `EquipmentDataManager.get_all_equipment()/get_equipment()`（Task 1）。
- Produces: `RunManager._roster_equipment:Dictionary`、`_offer_equipment:Dictionary`、`get_offer_equipment(crew_id:String)->EquipmentDefinition`、`get_equipment_for(crew_id:String)->EquipmentDefinition`。

- [ ] **Step 1: 写失败测试**

`tests/unit/run_equipment/run_equipment_test.gd`:

```gdscript
# RunManager 装备账本：招募滚装备（确定性）/ 记账 / 查询 / permadeath 擦除。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 20260622

func after_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

# AC-4：固定 seed 下，offer 装备确定可复现。
func test_offer_equipment_deterministic() -> void:
	RunManager._rng.seed = 777
	var offers_a := RunManager.get_recruit_offers()
	var first_id: String = offers_a[0].id
	var eq_a := RunManager.get_offer_equipment(first_id)
	RunManager._rng.seed = 777
	RunManager.get_recruit_offers()
	var eq_b := RunManager.get_offer_equipment(first_id)
	assert_bool(eq_a != null).is_true()
	assert_str(eq_a.id).is_equal(eq_b.id)

# AC-5：confirm_recruit 后 get_equipment_for 返回招募时滚到的装备。
func test_confirm_recruit_records_equipment() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	var offered_eq := RunManager.get_offer_equipment(chosen)
	RunManager.confirm_recruit(chosen)
	var held := RunManager.get_equipment_for(chosen)
	assert_bool(held != null).is_true()
	assert_str(held.id).is_equal(offered_eq.id)

# AC-6：permadeath 后 get_equipment_for 返回 null。
func test_permadeath_clears_equipment() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	RunManager.confirm_recruit(chosen)
	RunManager._on_crew_member_downed(chosen)
	assert_object(RunManager.get_equipment_for(chosen)).is_null()

# 起始船员无装备。
func test_starting_crew_has_no_equipment() -> void:
	var starter: String = RunManager.get_roster()[0].id
	assert_object(RunManager.get_equipment_for(starter)).is_null()
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_equipment/run_equipment_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -4
```
Expected: 运行错误（get_offer_equipment / get_equipment_for 不存在）。

- [ ] **Step 3: 加字段**

`src/autoloads/run_manager.gd`，在 `var _last_offers: ...` 行后加：

```gdscript
var _roster_equipment: Dictionary = {}   # crew_id → equipment_id（已招船员持有的装备）
var _offer_equipment: Dictionary = {}    # crew_id → equipment_id（本批候选滚到的装备）
```

- [ ] **Step 4: start_run 清账本**

在 `start_run()` 的 `_last_offers.clear()` 行后加：

```gdscript
	_roster_equipment.clear()
	_offer_equipment.clear()
```

- [ ] **Step 5: get_recruit_offers 滚装备**

在 `get_recruit_offers()` 末尾 `return offers` 之前（`_last_offers` 填充之后）插入：

```gdscript
	# 为每名候选随机滚一件装备（有放回；池空则不滚）。_rng 顺序确定 → 存档可复现。
	_offer_equipment.clear()
	var equip_pool := EquipmentDataManager.get_all_equipment()
	if not equip_pool.is_empty():
		for crew in offers:
			var pick := equip_pool[_rng.randi_range(0, equip_pool.size() - 1)]
			_offer_equipment[crew.id] = pick.id
```

- [ ] **Step 6: confirm_recruit 记账**

在 `confirm_recruit()` 的 `roster.append(def as CrewDefinition)` 行后（仍在 `if def is CrewDefinition:` 块内）加：

```gdscript
		var picked_eid := str(_offer_equipment.get(unit_id, ""))
		if picked_eid != "":
			_roster_equipment[unit_id] = picked_eid
```

并在该函数 `_last_offers.clear()` 行后加：

```gdscript
	_offer_equipment.clear()
```

- [ ] **Step 7: permadeath 擦除 + 查询方法**

在 `_on_crew_member_downed()` 末尾加：

```gdscript
	_roster_equipment.erase(crew_id)
```

在「存档」注释段（`# ── 存档（run-save #13）──`）之前加两个查询方法：

```gdscript
# 本批候选 crew_id 滚到的装备（招募卡 UI 用）；无则 null。
func get_offer_equipment(crew_id: String) -> EquipmentDefinition:
	var eid := str(_offer_equipment.get(crew_id, ""))
	if eid == "":
		return null
	return EquipmentDataManager.get_equipment(eid)

# 已招船员 crew_id 持有的装备（部署/战斗用）；无则 null。
func get_equipment_for(crew_id: String) -> EquipmentDefinition:
	var eid := str(_roster_equipment.get(crew_id, ""))
	if eid == "":
		return null
	return EquipmentDataManager.get_equipment(eid)
```

- [ ] **Step 8: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_equipment/run_equipment_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary" | tail -1
```
Expected: 4/4 PASSED；全量绿。

- [ ] **Step 9: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_equipment/
git commit -F - <<'EOF'
feat(run): equipment ledger — roll on recruit, record, query, clear on death

Story: equipment (#15)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 5: 部署落地（BattleMap.deploy_crew equipments 参数 + battle_scene 接线）

**Files:**
- Modify: `src/battle/battle_map.gd`、`src/battle/battle_scene.gd`
- Test: `tests/integration/equipment_battle/equipment_battle_test.gd`

**Interfaces:**
- Consumes: `RunManager.get_equipment_for()`（Task 4）、`UnitInstance.from_definition(def, equipment)` 与 `get_max_hp()`（Task 2）。
- Produces: `BattleMap.deploy_crew(crew_defs:Array, positions:Array, equipments:Array=[]) -> bool`。

- [ ] **Step 1: 写失败测试**

`tests/integration/equipment_battle/equipment_battle_test.gd`:

```gdscript
# 装备经 deploy_crew 上场后，UnitInstance 有效值含加成（AC-7）。
extends GdUnitTestSuite

func _crew_def() -> CrewDefinition:
	var d := CrewDefinition.new()
	d.id = "eqtest_crew"
	d.faction = "crew"
	d.unit_class = "bulwark"
	d.max_hp = 12
	d.base_damage = 2
	d.attack_range = 1
	d.move_range = 2
	d.class_action_id = "guard"
	d.recruit_pool_tier = "pool"
	return d

# AC-7：带 +3 血装备的船员部署后 get_max_hp = 基值+3。
func test_deployed_crew_has_equipment_stats() -> void:
	var grid := GridBoard.new()
	var tm := TurnManager.new()
	auto_free(tm)
	var bmap := BattleMap.new()
	auto_free(bmap)
	# 用最小可部署地图：直接走 deploy_crew 需要 MAP_READY，这里以单测视角验证 from_definition 装备透传足矣。
	var plate := EquipmentDataManager.get_equipment("eq_plate")
	var inst := UnitInstance.from_definition(_crew_def(), plate)
	assert_int(inst.get_max_hp()).is_equal(15)
	assert_int(inst.current_hp).is_equal(15)
```

> 说明：BattleMap.deploy_crew 全链路需 MAP_READY + 地图资源，集成成本高；本测试聚焦"装备透传到有效值"这一关键契约（from_definition + 访问器），deploy_crew 的 equipments 参数透传由代码审查 + 全量回归保障。

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/equipment_battle/equipment_battle_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -4
```
Expected: 通过或失败取决于 .tres——若 eq_plate 已在（Task 1），此测试在 Task 2 后即应 GREEN。**本任务真正交付物是 deploy_crew 接线**；测试用于守护契约。若已 GREEN，仍继续 Step 3-4 完成接线。

- [ ] **Step 3: 改 BattleMap.deploy_crew**

`src/battle/battle_map.gd`，把 `func deploy_crew(crew_defs: Array, positions: Array) -> bool:` 签名改为：

```gdscript
func deploy_crew(crew_defs: Array, positions: Array, equipments: Array = []) -> bool:
```

并把循环内 `var inst := UnitInstance.from_definition(crew_defs[i])` 改为：

```gdscript
		var eq: EquipmentDefinition = null
		if i < equipments.size():
			eq = equipments[i]
		var inst := UnitInstance.from_definition(crew_defs[i], eq)
```

- [ ] **Step 4: 改 battle_scene 接线**

`src/battle/battle_scene.gd` 的 `_deploy_run_crew()`，把构造循环与调用改为（加 equipments 并行数组）：

```gdscript
	var defs: Array[CrewDefinition] = []
	var positions: Array[Vector2i] = []
	var equipments: Array = []
	for i in n:
		defs.append(pending[i])
		positions.append(cells[i])
		equipments.append(RunManager.get_equipment_for(pending[i].id))
	_battle_map.deploy_crew(defs, positions, equipments)
```

`_spawn_all_views()` 把 max_hp 两处改用有效值：

```gdscript
		_unit_renderer.set_unit_max_hp(battle_id, inst.get_max_hp())
		view.set_hp(inst.current_hp, inst.get_max_hp())
```

- [ ] **Step 5: 跑测试 + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: 全量绿（含 equipment_battle）、0 错误。

- [ ] **Step 6: 提交**

```bash
git add src/battle/battle_map.gd src/battle/battle_scene.gd tests/integration/equipment_battle/
git commit -F - <<'EOF'
feat(battle): deploy crew with equipment, render effective max HP

Story: equipment (#15)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 6: 存档持久化 roster_equipment

**Files:**
- Modify: `src/autoloads/run_manager.gd`（`to_save_dict` / `load_from_save_dict`）
- Test: `tests/unit/run_equipment/run_equipment_save_test.gd`

**Interfaces:**
- Consumes: `_roster_equipment`（Task 4）、`EquipmentDataManager.get_equipment()`（Task 1）。

- [ ] **Step 1: 写失败测试**

`tests/unit/run_equipment/run_equipment_save_test.gd`:

```gdscript
# 装备账本进存档：to_save_dict→load 往返恢复；load 缺失 equip id 跳过。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()

func after_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

# AC-8：roster_equipment 往返恢复。
func test_roster_equipment_roundtrip() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	RunManager.confirm_recruit(chosen)
	var eq_before := RunManager.get_equipment_for(chosen)
	var d := RunManager.to_save_dict()
	RunManager.start_run()                 # 打乱清账本
	RunManager.load_from_save_dict(d)
	var eq_after := RunManager.get_equipment_for(chosen)
	assert_bool(eq_after != null).is_true()
	assert_str(eq_after.id).is_equal(eq_before.id)

# AC-8：load 缺失 equipment id → 该条目跳过、不崩。
func test_load_skips_missing_equipment_id() -> void:
	var d := {
		"roster": ["crew_swordsman_01"],
		"island_index": 0,
		"phase": "DEPLOYING",
		"roster_equipment": {"crew_swordsman_01": "eq_nonexistent_zzz"},
	}
	RunManager.load_from_save_dict(d)
	assert_object(RunManager.get_equipment_for("crew_swordsman_01")).is_null()
```

> 注：`crew_swordsman_01` 是起始船员，load roster 必含它（防御跳过仅针对缺失 crew/equip）。

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_equipment/run_equipment_save_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
```
Expected: `test_roster_equipment_roundtrip` FAILED（往返后为 null，因 to_save_dict 未存装备）。

- [ ] **Step 3: to_save_dict 加键**

`src/autoloads/run_manager.gd` 的 `to_save_dict()` 返回字典里，在 `"rng_state": str(_rng.state),` 行后加：

```gdscript
		"roster_equipment": _roster_equipment.duplicate(),
```

- [ ] **Step 4: load_from_save_dict 恢复**

在 `load_from_save_dict()` 末尾（`_rng.state = ...` 行后）加：

```gdscript
	# 装备账本恢复：仅保留 crew 仍在 roster、且 equipment 有定义的条目（缺失优雅跳过）。
	_roster_equipment.clear()
	var roster_id_set: Dictionary = {}
	for c in roster:
		roster_id_set[c.id] = true
	var re: Variant = d.get("roster_equipment", {})
	if re is Dictionary:
		for k in (re as Dictionary):
			var cid := str(k)
			var eid := str((re as Dictionary)[k])
			if roster_id_set.has(cid) and EquipmentDataManager.get_equipment(eid) != null:
				_roster_equipment[cid] = eid
```

- [ ] **Step 5: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_equipment/run_equipment_save_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary" | tail -1
```
Expected: 2/2 PASSED；全量绿。

- [ ] **Step 6: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_equipment/run_equipment_save_test.gd
git commit -F - <<'EOF'
feat(run): persist roster equipment in run save

Story: equipment (#15)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 7: 招募卡显示装备标签

**Files:**
- Modify: `src/ui/route_scene.gd`（`_show_recruit_offers` + 新增 `_equipment_summary`）
- Test: `tests/integration/equipment_recruit_ui/equipment_recruit_ui_test.gd`

**Interfaces:**
- Consumes: `RunManager.get_offer_equipment()`（Task 4）。

- [ ] **Step 1: 写失败测试**

`tests/integration/equipment_recruit_ui/equipment_recruit_ui_test.gd`:

```gdscript
# 招募卡文字含候选装备名（AC-9）。直驱 RECRUITING 分支（设 _phase）。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 4242
	RunManager._phase = RunManager.RunPhase.RUN_RECRUITING   # 直接置 RECRUITING（不发信号）

func after_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

# 递归收集树下所有 Button 文本。
func _all_button_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		if child is Button:
			out.append((child as Button).text)
		out.append_array(_all_button_texts(child))
	return out

# AC-9：至少一张招募卡文字含其装备的 display_name。
func test_recruit_card_shows_equipment_name() -> void:
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)   # _ready → RECRUITING → _show_recruit_offers（无阵亡，直通）
	assert_str(route._active_screen).is_equal("recruit")
	var texts := _all_button_texts(route)
	# 本批某候选的装备名应出现在某张卡文字中。
	var found := false
	for o in RunManager._last_offers:
		var eq := RunManager.get_offer_equipment(o)
		if eq == null:
			continue
		for t in texts:
			if t.contains(eq.display_name):
				found = true
	assert_bool(found).is_true()
```

> 注：`_show_recruit_offers` 内部会调 `get_recruit_offers()` 重滚一次 `_offer_equipment`；测试在 `add_child` 后再读 `get_offer_equipment`，与卡片同源同 rng 序，断言一致。

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/equipment_recruit_ui/equipment_recruit_ui_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
```
Expected: FAILED（卡片文字尚无装备名）。

- [ ] **Step 3: 改 _show_recruit_offers + 加摘要方法**

`src/ui/route_scene.gd`，把 `_show_recruit_offers()` 里候选按钮文字构造段：

```gdscript
	for o in offers:
		var crew := o as CrewDefinition
		var btn := Button.new()
		btn.text = "%s · %s · %s" % [crew.unit_class, crew.display_name, crew.battle_cry]
		btn.pressed.connect(_on_recruit_chosen.bind(crew.id))
		box.add_child(btn)
```

改为：

```gdscript
	for o in offers:
		var crew := o as CrewDefinition
		var btn := Button.new()
		var eq := RunManager.get_offer_equipment(crew.id)
		var eq_text := ("" if eq == null else " · " + _equipment_summary(eq))
		btn.text = "%s · %s · %s%s" % [crew.unit_class, crew.display_name, crew.battle_cry, eq_text]
		btn.pressed.connect(_on_recruit_chosen.bind(crew.id))
		box.add_child(btn)
```

在 `_on_recruit_chosen` 方法之后加摘要方法：

```gdscript
# 装备白盒摘要："名 +N攻 +N血 ..."（仅列非零增量）。
func _equipment_summary(eq: EquipmentDefinition) -> String:
	var parts: Array[String] = []
	if eq.hp_bonus != 0:
		parts.append("%+d血" % eq.hp_bonus)
	if eq.damage_bonus != 0:
		parts.append("%+d攻" % eq.damage_bonus)
	if eq.range_bonus != 0:
		parts.append("%+d射程" % eq.range_bonus)
	if eq.move_bonus != 0:
		parts.append("%+d移动" % eq.move_bonus)
	return "%s %s" % [eq.display_name, " ".join(parts)]
```

- [ ] **Step 4: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/equipment_recruit_ui/equipment_recruit_ui_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|Executed test|SCRIPT ERROR" | tail -4
```
Expected: 1/1 PASSED；全量绿、0 错误/孤儿（AC-10）。

- [ ] **Step 5: 提交**

```bash
git add src/ui/route_scene.gd tests/integration/equipment_recruit_ui/
git commit -F - <<'EOF'
feat(route): show equipment label on recruit cards

Story: equipment (#15)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**Spec coverage:**
- Rule 1 EquipmentDefinition → Task 1 ✓
- Rule 2 EquipmentDataManager + autoload → Task 1 ✓
- Rule 3 4 件起始装备 .tres → Task 1 ✓
- Rule 4 UnitInstance 有效值 + from_definition 参数 + 钳 0 → Task 2 ✓
- Rule 5 战斗读值切换（4 文件）→ Task 3；battle_scene 的 max_hp → Task 5 ✓
- Rule 6 RunManager 账本（滚/记账/查询/起始无装备/permadeath 擦除）→ Task 4 ✓
- Rule 7 部署落地（deploy_crew equipments + battle_scene 接线 + 有效 max_hp 渲染）→ Task 5 ✓
- Rule 8 招募卡 UI → Task 7 ✓
- Rule 9 存档 roster_equipment（存/恢复/缺失跳过）→ Task 6 ✓
- 边界：池空（Task 4 Step 5 守卫）/ load 缺失 id（Task 6 Step 4 + 测试）/ 敌方 null（Task 2 访问器）/ 起始无装备（Task 4 测试）/ 不叠加（单值映射）/ 负值钳 0（Task 2 测试）✓
- AC-1..10 → Task 1(AC-1) / Task 2(AC-2,3) / Task 4(AC-4,5,6) / Task 5(AC-7) / Task 6(AC-8) / Task 7(AC-9) / 各任务全量回归(AC-10) ✓

**Placeholder scan:** 无 TBD/TODO；每步含完整代码/命令+期望。✓

**Type consistency:**
- `from_definition(def, equipment:EquipmentDefinition=null)` 在 Task 2 定义，Task 5 调用一致。
- `get_max_hp/get_base_damage/get_attack_range/get_move_range` 在 Task 2 定义，Task 3/5 调用一致。
- `get_offer_equipment/get_equipment_for(crew_id)->EquipmentDefinition` 在 Task 4 定义，Task 5/6/7 调用一致。
- `deploy_crew(crew_defs, positions, equipments=[])` 在 Task 5 定义并调用一致。
- `_roster_equipment/_offer_equipment` Dictionary 在 Task 4 定义，Task 6 存档读写一致。
- `_equipment_summary(eq:EquipmentDefinition)->String` 在 Task 7 定义并就地使用。
- 静态类型：deploy_crew 内 `var eq: EquipmentDefinition = null` 避 Variant 三元；load 内 `var re: Variant` + `is Dictionary` 守卫；访问器三元在 int 上下文安全。✓
