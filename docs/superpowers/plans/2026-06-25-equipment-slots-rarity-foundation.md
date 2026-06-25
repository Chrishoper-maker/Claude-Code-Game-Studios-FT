# 装备地基重构：9 槽 + 5 稀有度（②a）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「一人一件装备」升级为 9 固定槽 + 5 级稀有度的装备地基，含 31 种装备、多槽有效值累加、招募「滚 8 选 2」加权获取、战斗/存档适配（含旧档迁移）。

**Architecture:** `EquipmentDefinition` 加 `rarity/slot/set_id` 字段与 `Rarity`/`Slot` 枚举；`EquipmentDataManager` 加按稀有度/槽过滤查询。`UnitInstance.equipment` 由单件改为 `{slot:def}` 字典，四个有效值访问器对所有已装槽求和。`RunManager._roster_equipment` 由 `crew_id→eid` 升级为 `crew_id→{slot:eid}`；招募改为 `roll_recruit_equipment()` 按权重滚 8 件（同槽≤2）、`confirm_recruit(unit_id, equip_picks)` 选 2 件装入。存档 `roster_equipment` 嵌套化 + 旧扁平 id 迁移。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。autoload 单例（RunManager / EquipmentDataManager / UnitDataManager / MetaProgress / EventBus）。

## Global Constraints

- 引擎 Godot 4.6.3；测试 GdUnit4，跑 `godot --headless --import` 后 `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`。
- 命名：类 PascalCase、变量/函数 snake_case、信号过去式 snake_case、常量 UPPER_SNAKE_CASE。
- GDScript 静态类型（`:=` / 显式类型注解），公共 API 写中文 doc 注释。
- 数值数据驱动：装备数值进 `.tres`，不硬编码。
- 确定性：所有随机走 `RunManager._rng`；存档 `rng_state` 复现。测试不依赖真实时间/真实 `user://run.json`（注入 `_save_path`、`_autosave_enabled=false`）。
- autoload 脚本不声明 `class_name`；数据/运行时类声明 `class_name`。
- 提交用 Conventional Commits，body 引用 `Story: equipment-slots-rarity-foundation`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 9 槽枚举 `Slot`：MAIN_WEAPON=0 / OFF_WEAPON=1 / HEAD=2 / ARMOR=3 / GLOVES=4 / LEGS=5 / BOOTS=6 / RING=7 / NECKLACE=8。
- 5 稀有度枚举 `Rarity`：COMMON=0 / RARE=1 / EPIC=2 / ANCIENT=3 / LEGENDARY=4。
- 招募滚装权重（百分比）：LEGENDARY 2 / ANCIENT 8 / EPIC 15 / RARE 25 / COMMON 50（合计 100）。滚 8 件、同槽≤2、玩家选 2 件（不同槽）。

---

### Task 1: EquipmentDefinition 字段/枚举 + DataManager 过滤查询

**Files:**
- Modify: `src/data/equipment_definition.gd`
- Modify: `src/autoloads/equipment_data_manager.gd`
- Modify: `assets/data/equipment/eq_cutlass.tres`, `eq_plate.tres`, `eq_boots.tres`, `eq_spyglass.tres`
- Test: `tests/unit/equipment_data/equipment_data_query_test.gd` (create)

**Interfaces:**
- Produces:
  - `EquipmentDefinition.Rarity`（enum：COMMON/RARE/EPIC/ANCIENT/LEGENDARY = 0..4）
  - `EquipmentDefinition.Slot`（enum：MAIN_WEAPON/OFF_WEAPON/HEAD/ARMOR/GLOVES/LEGS/BOOTS/RING/NECKLACE = 0..8）
  - `EquipmentDefinition` 新 `@export` 字段：`rarity:int`、`slot:int`、`set_id:String`
  - `EquipmentDataManager.get_equipment_by_rarity(rarity:int) -> Array[EquipmentDefinition]`
  - `EquipmentDataManager.get_equipment_by_slot(slot:int) -> Array[EquipmentDefinition]`

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/equipment_data/equipment_data_query_test.gd`：

```gdscript
extends GdUnitTestSuite

# 校验 EquipmentDataManager 按稀有度/槽过滤查询（用现有 4 件普通装备）。
func test_query_by_rarity_returns_only_that_rarity() -> void:
	var commons := EquipmentDataManager.get_equipment_by_rarity(EquipmentDefinition.Rarity.COMMON)
	assert_bool(commons.size() >= 4).is_true()  # 现有 4 件均普通
	for eq in commons:
		assert_int(eq.rarity).is_equal(EquipmentDefinition.Rarity.COMMON)

func test_query_by_slot_returns_only_that_slot() -> void:
	# 弯刀(eq_cutlass) 归主武器槽
	var weapons := EquipmentDataManager.get_equipment_by_slot(EquipmentDefinition.Slot.MAIN_WEAPON)
	var ids: Array[String] = []
	for eq in weapons:
		assert_int(eq.slot).is_equal(EquipmentDefinition.Slot.MAIN_WEAPON)
		ids.append(eq.id)
	assert_array(ids).contains(["eq_cutlass"])

func test_existing_equipment_has_default_fields() -> void:
	var plate := EquipmentDataManager.get_equipment("eq_plate")
	assert_object(plate).is_not_null()
	assert_int(plate.rarity).is_equal(EquipmentDefinition.Rarity.COMMON)
	assert_str(plate.set_id).is_equal("")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/equipment_data`
Expected: FAIL（`Rarity`/`Slot`/`get_equipment_by_rarity` 未定义）。

- [ ] **Step 3: 加枚举与字段**

`src/data/equipment_definition.gd` 改为：

```gdscript
# 装备定义模板（只读静态数据）。纯数值增量 + 稀有度/槽位/套装归属。
# 运行时不写回；由 EquipmentDataManager 扫描缓存。
class_name EquipmentDefinition
extends Resource

enum Rarity { COMMON, RARE, EPIC, ANCIENT, LEGENDARY }   # 0..4（白/蓝/紫/橙/红）
enum Slot { MAIN_WEAPON, OFF_WEAPON, HEAD, ARMOR, GLOVES, LEGS, BOOTS, RING, NECKLACE }  # 0..8

@export var id: String
@export var display_name: String
@export var hp_bonus: int
@export var damage_bonus: int
@export var range_bonus: int
@export var move_bonus: int
@export var rarity: int = Rarity.COMMON   # Rarity 枚举值
@export var slot: int = Slot.MAIN_WEAPON   # Slot 枚举值
@export var set_id: String = ""            # 套装归属（②a 留空，②b 填充）
```

- [ ] **Step 4: 加过滤查询 + 范围校验**

`src/autoloads/equipment_data_manager.gd`：在 `get_all_equipment()` 之后加两个查询方法：

```gdscript
# 按稀有度过滤（Rarity 枚举值）。
func get_equipment_by_rarity(rarity: int) -> Array[EquipmentDefinition]:
	var out: Array[EquipmentDefinition] = []
	for def in get_all_equipment():
		if def.rarity == rarity:
			out.append(def)
	return out

# 按装备槽过滤（Slot 枚举值）。
func get_equipment_by_slot(slot: int) -> Array[EquipmentDefinition]:
	var out: Array[EquipmentDefinition] = []
	for def in get_all_equipment():
		if def.slot == slot:
			out.append(def)
	return out
```

在 `_validate_all()` 的 `for def in _all:` 重复 id 校验循环中，追加 rarity/slot 范围校验（紧接 `seen_ids[def.id] = true` 之后）：

```gdscript
		if def.rarity < 0 or def.rarity > EquipmentDefinition.Rarity.LEGENDARY:
			push_error("EquipmentData validation error: %s — rarity 越界 %d" % [def.id, def.rarity])
			has_error = true
		if def.slot < 0 or def.slot > EquipmentDefinition.Slot.NECKLACE:
			push_error("EquipmentData validation error: %s — slot 越界 %d" % [def.id, def.slot])
			has_error = true
```

- [ ] **Step 5: 更新现有 4 件 .tres**

为 4 件添加 `rarity`/`slot`/`set_id` 三行（紧跟 `move_bonus` 之后）。各文件追加：
- `eq_cutlass.tres`：`rarity = 0` / `slot = 0`（主武器）/ `set_id = ""`
- `eq_plate.tres`：`rarity = 0` / `slot = 3`（护甲）/ `set_id = ""`
- `eq_boots.tres`：`rarity = 0` / `slot = 6`（靴子）/ `set_id = ""`
- `eq_spyglass.tres`：`rarity = 0` / `slot = 7`（戒指）/ `set_id = ""`

例（`eq_cutlass.tres` 的 `[resource]` 段末尾）：

```
move_bonus = 0
rarity = 0
slot = 0
set_id = ""
```

- [ ] **Step 6: 跑测试确认通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/equipment_data`
Expected: PASS（3 测试绿）。

- [ ] **Step 7: 提交**

```bash
git add src/data/equipment_definition.gd src/autoloads/equipment_data_manager.gd assets/data/equipment/ tests/unit/equipment_data/
git commit -m "feat(equipment): add rarity/slot/set_id fields + data-manager filters (2a)

Story: equipment-slots-rarity-foundation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: 编写 31 种装备数据池

**Files:**
- Create: 27 个新 `assets/data/equipment/eq_*.tres`（见下表，除现有 4 件外）
- Test: `tests/unit/equipment_data/equipment_pool_smoke_test.gd` (create)

**Interfaces:**
- Consumes: Task 1 的 `EquipmentDefinition` 字段、`EquipmentDataManager.get_equipment_by_rarity`
- Produces: 31 件装备资源（普10/稀8/史5/稀世5/传3），供 Task 4 招募滚装、后续 ②c/②b 使用

**装备总表**（slot/rarity 用枚举 int；现有 4 件已在 Task 1 更新，本任务造其余 27 件）：

| id | display_name | slot | rarity | hp | dmg | rng | mv |
|---|---|---|---|---|---|---|---|
| eq_cutlass★ | 弯刀 | 0 | 0 | 0 | 1 | 0 | 0 |
| eq_dagger | 匕首 | 1 | 0 | 0 | 1 | 0 | 0 |
| eq_cap | 水手帽 | 2 | 0 | 2 | 0 | 0 | 0 |
| eq_plate★ | 板甲 | 3 | 0 | 3 | 0 | 0 | 0 |
| eq_clothglove | 粗布手套 | 4 | 0 | 0 | 1 | 0 | 0 |
| eq_clothwrap | 布绑腿 | 5 | 0 | 1 | 0 | 0 | 0 |
| eq_boots★ | 轻靴 | 6 | 0 | 0 | 0 | 0 | 1 |
| eq_spyglass★ | 望远镜 | 7 | 0 | 0 | 0 | 1 | 0 |
| eq_woodcharm | 木护符 | 8 | 0 | 2 | 0 | 0 | 0 |
| eq_strawsandals | 草鞋 | 6 | 0 | 0 | 0 | 0 | 1 |
| eq_sabre | 军刀 | 0 | 1 | 0 | 2 | 0 | 0 |
| eq_flintlock | 燧发枪 | 1 | 1 | 0 | 0 | 2 | 0 |
| eq_ironhelm | 铁盔 | 2 | 1 | 4 | 0 | 0 | 0 |
| eq_chainmail | 锁子甲 | 3 | 1 | 5 | 0 | 0 | 0 |
| eq_warglove | 战斗护手 | 4 | 1 | 0 | 2 | 0 | 0 |
| eq_greaves | 护胫 | 5 | 1 | 3 | 0 | 0 | 0 |
| eq_swiftboots | 疾风靴 | 6 | 1 | 0 | 0 | 0 | 2 |
| eq_signet | 印戒 | 7 | 1 | 2 | 1 | 0 | 0 |
| eq_masterblade | 名匠刀 | 0 | 2 | 0 | 3 | 0 | 0 |
| eq_doublebarrel | 双管枪 | 1 | 2 | 0 | 1 | 2 | 0 |
| eq_fullhelm | 全覆盔 | 2 | 2 | 6 | 0 | 0 | 0 |
| eq_dragonscale | 龙鳞甲 | 3 | 2 | 8 | 0 | 0 | 0 |
| eq_compassring | 罗盘戒 | 7 | 2 | 0 | 0 | 1 | 1 |
| eq_stormblade | 风暴之刃 | 0 | 3 | 0 | 4 | 1 | 0 |
| eq_seacloak | 海潮披风 | 3 | 3 | 8 | 0 | 0 | 1 |
| eq_runicglove | 符文护手 | 4 | 3 | 2 | 3 | 0 | 0 |
| eq_voyagerwrap | 远航绑腿 | 5 | 3 | 3 | 0 | 0 | 2 |
| eq_tideamulet | 潮汐护符 | 8 | 3 | 4 | 1 | 0 | 0 |
| eq_dragonslayer | 屠龙 | 0 | 4 | 0 | 4 | 0 | 0 |
| eq_poseidoncharm | 海神护符 | 8 | 4 | 6 | 0 | 1 | 0 |
| eq_galewraps | 疾风绑腿 | 5 | 4 | 2 | 0 | 0 | 2 |

★ = 现有文件（Task 1 已更新，不重复创建）。本任务创建其余 **27 件**。

- [ ] **Step 1: 写失败 smoke 测试**

创建 `tests/unit/equipment_data/equipment_pool_smoke_test.gd`：

```gdscript
extends GdUnitTestSuite

# 校验完整 31 件装备池的稀有度分布与基本不变量。
func test_total_count_is_31() -> void:
	assert_int(EquipmentDataManager.get_all_equipment().size()).is_equal(31)

func test_rarity_distribution_10_8_5_5_3() -> void:
	assert_int(EquipmentDataManager.get_equipment_by_rarity(0).size()).is_equal(10)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(1).size()).is_equal(8)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(2).size()).is_equal(5)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(3).size()).is_equal(5)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(4).size()).is_equal(3)

func test_all_loaded_and_unique() -> void:
	assert_bool(EquipmentDataManager.is_loaded).is_true()
	var seen: Dictionary = {}
	for eq in EquipmentDataManager.get_all_equipment():
		assert_bool(seen.has(eq.id)).is_false()
		seen[eq.id] = true
		assert_int(eq.slot).is_between(0, 8)
		assert_int(eq.rarity).is_between(0, 4)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/equipment_data/equipment_pool_smoke_test.gd`
Expected: FAIL（当前仅 4 件）。

- [ ] **Step 3: 创建 27 个 .tres**

每个文件按此模板（以 `eq_dagger.tres` 为例），路径 `assets/data/equipment/<id>.tres`，字段取自上表对应行：

```
[gd_resource type="Resource" script_class="EquipmentDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/equipment_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "eq_dagger"
display_name = "匕首"
hp_bonus = 0
damage_bonus = 1
range_bonus = 0
move_bonus = 0
rarity = 0
slot = 1
set_id = ""
```

逐行照表填 `id/display_name/slot/rarity/hp_bonus/damage_bonus/range_bonus/move_bonus`，`set_id = ""`。共 27 个文件。

- [ ] **Step 4: 导入并跑测试确认通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/equipment_data`
Expected: PASS（含 Task 1 的 3 测试 + 本任务 3 测试，导入零错误）。

- [ ] **Step 5: 提交**（含 `.import`/`.uid` 旁车文件）

```bash
git add assets/data/equipment/ tests/unit/equipment_data/equipment_pool_smoke_test.gd
git commit -m "feat(equipment): author 31-item pool (10/8/5/5/3 by rarity) (2a)

Story: equipment-slots-rarity-foundation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 模型迁移——UnitInstance 多槽 + RunManager 槽字典存储 + 战斗/存档接线

**Files:**
- Modify: `src/data/unit_instance.gd`
- Modify: `src/autoloads/run_manager.gd`（`_roster_equipment` 注释、`get_equipment_for`、`confirm_recruit`、`to_save_dict`、`load_from_save_dict`；删除 `get_offer_equipment` 留到 Task 4）
- Modify: `src/battle/battle_map.gd:73-75`（部署传字典）
- Test: `tests/unit/unit_instance_equipment/unit_instance_equipment_test.gd`（改写为多槽）
- Test: `tests/unit/run_equipment/run_equipment_save_test.gd`（改写为嵌套 + 旧档迁移）
- Test: `tests/unit/run_equipment/run_equipment_test.gd`（`get_equipment_for` 返回字典 + confirm_recruit 嵌套存储）

**Interfaces:**
- Consumes: Task 1/2 的装备字段与池
- Produces:
  - `UnitInstance.equipment: Dictionary`（`slot:int → EquipmentDefinition`）
  - `UnitInstance.from_definition(def: UnitDefinition, equipment: Dictionary = {}) -> UnitInstance`
  - `RunManager.get_equipment_for(crew_id: String) -> Dictionary`（`slot:int → EquipmentDefinition`）
  - `RunManager._roster_equipment`：`crew_id → { slot:int → eid:String }`
  - 存档 `roster_equipment` 嵌套格式 + 旧扁平 id 迁移

- [ ] **Step 1: 改写 UnitInstance 多槽测试（失败）**

把 `tests/unit/unit_instance_equipment/unit_instance_equipment_test.gd` 改为多槽断言（替换其中构造单件装备的用法）：

```gdscript
extends GdUnitTestSuite

func _crew() -> UnitDefinition:
	return UnitDataManager.get_unit("swordsman_01")  # 既有起始剑士

func _eq(id: String) -> EquipmentDefinition:
	return EquipmentDataManager.get_equipment(id)

func test_no_equipment_uses_base_values() -> void:
	var inst := UnitInstance.from_definition(_crew(), {})
	assert_int(inst.get_max_hp()).is_equal(_crew().max_hp)

func test_single_slot_adds_bonus() -> void:
	var slots := { EquipmentDefinition.Slot.ARMOR: _eq("eq_plate") }  # +3血
	var inst := UnitInstance.from_definition(_crew(), slots)
	assert_int(inst.get_max_hp()).is_equal(_crew().max_hp + 3)

func test_multi_slot_sums_all_bonuses() -> void:
	var slots := {
		EquipmentDefinition.Slot.ARMOR: _eq("eq_plate"),       # +3血
		EquipmentDefinition.Slot.MAIN_WEAPON: _eq("eq_cutlass"),# +1攻
		EquipmentDefinition.Slot.BOOTS: _eq("eq_boots"),        # +1移动
	}
	var inst := UnitInstance.from_definition(_crew(), slots)
	assert_int(inst.get_max_hp()).is_equal(_crew().max_hp + 3)
	assert_int(inst.get_base_damage()).is_equal(_crew().base_damage + 1)
	assert_int(inst.get_move_range()).is_equal(_crew().move_range + 1)

func test_bonus_clamped_at_zero() -> void:
	# 即便基值很低也不为负（沿用现有钳零语义）
	var inst := UnitInstance.from_definition(_crew(), {})
	assert_int(inst.get_attack_range()).is_greater_equal(0)
```

> 若 `swordsman_01` id 不符，先 `grep recruit_pool_tier assets/data/units` 取一个起始 crew id 替换。

- [ ] **Step 2: 跑测试确认失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/unit_instance_equipment`
Expected: FAIL（`from_definition` 仍要求单件 `EquipmentDefinition`）。

- [ ] **Step 3: 改 UnitInstance 为多槽**

`src/data/unit_instance.gd`：把 `equipment` 字段与 `from_definition`、四个访问器改为：

```gdscript
var equipment: Dictionary = {}   # slot(int) → EquipmentDefinition（仅 crew；敌方/无装备为空）

# 由模板生成运行时实例。equipment 为 {slot:int → EquipmentDefinition}，默认空。
static func from_definition(def: UnitDefinition, equipment: Dictionary = {}) -> UnitInstance:
	var inst := UnitInstance.new()
	inst.definition = def
	inst.equipment = equipment
	inst.current_hp = inst.get_max_hp()
	inst.grid_position = SENTINEL_POS
	inst.has_moved = false
	inst.has_acted = false
	inst.has_used_verb = def.class_action_id == ""
	inst.is_alive = true
	inst.behavior_type = ""
	inst.home_pos = SENTINEL_POS
	return inst

# 所有已装槽某增量字段之和（hp_bonus/damage_bonus/range_bonus/move_bonus）。
func _equipment_bonus(field: String) -> int:
	var total := 0
	for s in equipment:
		var eq: EquipmentDefinition = equipment[s]
		if eq != null:
			total += int(eq.get(field))
	return total

func get_max_hp() -> int:
	return maxi(0, definition.max_hp + _equipment_bonus("hp_bonus"))

func get_base_damage() -> int:
	return maxi(0, definition.base_damage + _equipment_bonus("damage_bonus"))

func get_attack_range() -> int:
	return maxi(0, definition.attack_range + _equipment_bonus("range_bonus"))

func get_move_range() -> int:
	return maxi(0, definition.move_range + _equipment_bonus("move_bonus"))
```

- [ ] **Step 4: 接线战斗部署**

`src/battle/battle_map.gd` 第 73-75 行附近，把单件取用改为字典：

```gdscript
	for i in crew_defs.size():
		var eq: Dictionary = {}
		if i < equipments.size() and equipments[i] is Dictionary:
			eq = equipments[i]
		var inst := UnitInstance.from_definition(crew_defs[i], eq)
```

`src/battle/battle_scene.gd:62` 无需改（`get_equipment_for` 现返回字典，`equipments.append(...)` 自然存字典）。敌方 `from_definition(def)`（battle_map.gd:125）保持不变（默认 `{}`）。

- [ ] **Step 5: 跑 UnitInstance 测试确认通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/unit_instance_equipment`
Expected: PASS。

- [ ] **Step 6: 写 RunManager 槽字典存储测试（失败）**

改写 `tests/unit/run_equipment/run_equipment_test.gd` 中涉及 `get_equipment_for`/`confirm_recruit` 单件的断言为字典版（保留招募滚装相关到 Task 4），新增：

```gdscript
func test_get_equipment_for_returns_slot_dict() -> void:
	var rm := RunManager
	rm._roster_equipment = { "gunner_01": { EquipmentDefinition.Slot.MAIN_WEAPON: "eq_cutlass" } }
	var slots := rm.get_equipment_for("gunner_01")
	assert_int(slots.size()).is_equal(1)
	assert_object(slots[EquipmentDefinition.Slot.MAIN_WEAPON]).is_not_null()
	assert_str(slots[EquipmentDefinition.Slot.MAIN_WEAPON].id).is_equal("eq_cutlass")

func test_get_equipment_for_missing_crew_returns_empty() -> void:
	RunManager._roster_equipment = {}
	assert_int(RunManager.get_equipment_for("nobody").size()).is_equal(0)
```

> 若 `gunner_01` 不存在，用任一 pool crew id；测试只读 `_roster_equipment`，不依赖该 crew 在 roster。

- [ ] **Step 7: 改 RunManager get_equipment_for 为字典**

`src/autoloads/run_manager.gd`：把 `_roster_equipment` 注释改为 `# crew_id → { slot:int → equipment_id }`，并改 `get_equipment_for`：

```gdscript
# 已招船员 crew_id 持有的装备（部署/战斗用）；返回 {slot:int → EquipmentDefinition}，无则空 {}。
func get_equipment_for(crew_id: String) -> Dictionary:
	var out: Dictionary = {}
	var slots: Variant = _roster_equipment.get(crew_id, {})
	if slots is Dictionary:
		for s in (slots as Dictionary):
			var eid := str((slots as Dictionary)[s])
			var def := EquipmentDataManager.get_equipment(eid)
			if def != null:
				out[int(s)] = def
	return out
```

改 `confirm_recruit`：把 `_offer_equipment` 单件写入改为按 slot 嵌套（暂仍用 `_offer_equipment`，Task 4 再换源）：

```gdscript
	if def is CrewDefinition:
		roster.append(def as CrewDefinition)
		var picked_eid := str(_offer_equipment.get(unit_id, ""))
		if picked_eid != "":
			var edef := EquipmentDataManager.get_equipment(picked_eid)
			if edef != null:
				_roster_equipment[unit_id] = { edef.slot: picked_eid }
```

- [ ] **Step 8: 改存档为嵌套 + 旧档迁移**

`to_save_dict()`：把 `"roster_equipment": _roster_equipment.duplicate(),` 改为 `"roster_equipment": _roster_equipment.duplicate(true),`（深拷贝嵌套）。

`load_from_save_dict()` 的装备恢复段（当前 387-393 行）替换为：

```gdscript
	var re: Variant = d.get("roster_equipment", {})
	if re is Dictionary:
		for k in (re as Dictionary):
			var cid := str(k)
			if not roster_id_set.has(cid):
				continue
			var val: Variant = (re as Dictionary)[k]
			var slots: Dictionary = {}
			if val is Dictionary:
				for s in (val as Dictionary):
					var eid := str((val as Dictionary)[s])
					if EquipmentDataManager.get_equipment(eid) != null:
						slots[int(s)] = eid
			else:
				# 旧档迁移：单 eid → 按其 slot 放入
				var eid := str(val)
				var edef := EquipmentDataManager.get_equipment(eid)
				if edef != null:
					slots[edef.slot] = eid
			if not slots.is_empty():
				_roster_equipment[cid] = slots
```

- [ ] **Step 9: 改写存档测试（嵌套 + 迁移）**

`tests/unit/run_equipment/run_equipment_save_test.gd` 替换为：

```gdscript
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false

func test_nested_roster_equipment_roundtrips() -> void:
	var rm := RunManager
	rm.start_run()
	var crew_id := rm.roster[0].id
	rm._roster_equipment = { crew_id: { EquipmentDefinition.Slot.ARMOR: "eq_plate", EquipmentDefinition.Slot.MAIN_WEAPON: "eq_cutlass" } }
	var d := rm.to_save_dict()
	rm._roster_equipment = {}
	rm.load_from_save_dict(d)
	var slots: Dictionary = rm._roster_equipment[crew_id]
	assert_int(slots.size()).is_equal(2)
	assert_str(str(slots[EquipmentDefinition.Slot.ARMOR])).is_equal("eq_plate")

func test_legacy_flat_id_migrates_to_slot() -> void:
	var rm := RunManager
	rm.start_run()
	var crew_id := rm.roster[0].id
	# 旧档：roster_equipment 为 crew_id → 单 eid
	var legacy := rm.to_save_dict()
	legacy["roster_equipment"] = { crew_id: "eq_boots" }   # 旧扁平格式
	rm._roster_equipment = {}
	rm.load_from_save_dict(legacy)
	var slots: Dictionary = rm._roster_equipment[crew_id]
	assert_str(str(slots[EquipmentDefinition.Slot.BOOTS])).is_equal("eq_boots")

func test_missing_definition_dropped() -> void:
	var rm := RunManager
	rm.start_run()
	var crew_id := rm.roster[0].id
	var d := rm.to_save_dict()
	d["roster_equipment"] = { crew_id: { EquipmentDefinition.Slot.ARMOR: "eq_does_not_exist" } }
	rm._roster_equipment = {}
	rm.load_from_save_dict(d)
	assert_bool(rm._roster_equipment.has(crew_id)).is_false()
```

- [ ] **Step 10: 跑相关测试确认通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_equipment -a res://tests/unit/unit_instance_equipment`
Expected: PASS。

- [ ] **Step 11: 跑全量回归，修任何因 from_definition 旧签名/单件 roster_equipment 而挂的既有测试**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
排查并修正：任何向 `from_definition(def, <单件 EquipmentDefinition>)` 传第二参的调用 → 改为传 `{slot: def}` 字典；任何断言 `get_equipment_for` 返回单件的旧测试 → 改为字典。
Expected: 全量 PASS（`get_offer_equipment` 相关测试此时可能仍引用旧字段 → 留到 Task 4 改写，若编译失败则先在本步注释掉对应断言并标 TODO(Task4)，Task 4 复原）。

- [ ] **Step 12: 提交**

```bash
git add src/data/unit_instance.gd src/autoloads/run_manager.gd src/battle/battle_map.gd tests/
git commit -m "feat(equipment): migrate to 9-slot model (UnitInstance + RunManager + save) (2a)

Story: equipment-slots-rarity-foundation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 招募「滚 8 选 2」加权获取（同槽≤2）

**Files:**
- Modify: `src/autoloads/run_manager.gd`（删 `_offer_equipment`/`get_offer_equipment`、改 `get_recruit_offers` 不滚装、加 `roll_recruit_equipment`/权重常量/`confirm_recruit` 加 `equip_picks` 参）
- Test: `tests/unit/run_equipment/run_equipment_roll_test.gd`（create）
- Test: `tests/unit/run_equipment/run_equipment_test.gd`（移除 `get_offer_equipment` 旧断言、加 confirm_recruit picks 断言）

**Interfaces:**
- Consumes: Task 1/2/3
- Produces:
  - `RunManager.roll_recruit_equipment() -> Array[EquipmentDefinition]`（滚 8 件，写 `_pending_recruit_equip: Array[String]`）
  - `RunManager.confirm_recruit(unit_id: String, equip_picks: Array = []) -> void`（picks 为 eid 数组，限不同槽装入）
  - 常量 `RECRUIT_EQUIP_ROLL=8`、`RECRUIT_EQUIP_PICK=2`、`SAME_SLOT_CAP=2`

- [ ] **Step 1: 写滚装测试（失败）**

创建 `tests/unit/run_equipment/run_equipment_roll_test.gd`：

```gdscript
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._rng.seed = 12345   # 确定性

func test_rolls_exactly_8() -> void:
	var rolled := RunManager.roll_recruit_equipment()
	assert_int(rolled.size()).is_equal(8)

func test_same_slot_capped_at_2() -> void:
	var rolled := RunManager.roll_recruit_equipment()
	var slot_counts: Dictionary = {}
	for eq in rolled:
		slot_counts[eq.slot] = int(slot_counts.get(eq.slot, 0)) + 1
	for s in slot_counts:
		assert_int(int(slot_counts[s])).is_less_equal(2)

func test_deterministic_same_seed_same_roll() -> void:
	RunManager._rng.seed = 777
	var a := RunManager.roll_recruit_equipment()
	RunManager._rng.seed = 777
	var b := RunManager.roll_recruit_equipment()
	var ida: Array[String] = []
	var idb: Array[String] = []
	for e in a: ida.append(e.id)
	for e in b: idb.append(e.id)
	assert_array(ida).is_equal(idb)

func test_weighted_distribution_skews_common() -> void:
	# 大样本：普通(0)占比应远高于传奇(4)
	var counts := {0:0, 1:0, 2:0, 3:0, 4:0}
	RunManager._rng.seed = 1
	for n in 200:
		for eq in RunManager.roll_recruit_equipment():
			counts[eq.rarity] += 1
	assert_int(counts[0]).is_greater(counts[4])
	assert_int(counts[1]).is_greater(counts[4])
```

- [ ] **Step 2: 跑测试确认失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_equipment/run_equipment_roll_test.gd`
Expected: FAIL（`roll_recruit_equipment` 未定义）。

- [ ] **Step 3: 实现滚装 + 权重 + 同槽约束**

`src/autoloads/run_manager.gd`：在常量区加：

```gdscript
const RECRUIT_EQUIP_ROLL := 8
const RECRUIT_EQUIP_PICK := 2
const SAME_SLOT_CAP := 2
# 招募滚装稀有度权重（百分比）；键为 Rarity 枚举值。
const _RARITY_WEIGHTS := { 4: 2, 3: 8, 2: 15, 1: 25, 0: 50 }
```

在变量区把 `var _offer_equipment ...` 一行替换为：

```gdscript
var _pending_recruit_equip: Array[String] = []   # 本次招募滚出的 8 件 eid（玩家从中选 2）
```

加方法（放在 `get_recruit_offers` 之后）：

```gdscript
# 按权重抽一个稀有度（高→低累计）。
func _roll_rarity() -> int:
	var total := 0
	for r in _RARITY_WEIGHTS:
		total += int(_RARITY_WEIGHTS[r])
	var roll := _rng.randi_range(1, total)
	var acc := 0
	for r in [4, 3, 2, 1, 0]:
		acc += int(_RARITY_WEIGHTS[r])
		if roll <= acc:
			return r
	return 0

# 某稀有度子池；空则降级到相邻较低稀有度，直至非空或耗尽。
func _equip_subpool(rarity: int) -> Array[EquipmentDefinition]:
	var r := rarity
	while r >= 0:
		var sub := EquipmentDataManager.get_equipment_by_rarity(r)
		if not sub.is_empty():
			return sub
		r -= 1
	return []

# 招募滚 8 件：权重稀有度 + 同槽≤2。写 _pending_recruit_equip，返回定义数组（UI 用）。
func roll_recruit_equipment() -> Array[EquipmentDefinition]:
	_pending_recruit_equip.clear()
	var result: Array[EquipmentDefinition] = []
	var slot_counts: Dictionary = {}
	var attempts := 0
	var max_attempts := RECRUIT_EQUIP_ROLL * 30
	while result.size() < RECRUIT_EQUIP_ROLL and attempts < max_attempts:
		attempts += 1
		var sub := _equip_subpool(_roll_rarity())
		if sub.is_empty():
			break
		var pick := sub[_rng.randi_range(0, sub.size() - 1)]
		var sc := int(slot_counts.get(pick.slot, 0))
		if sc >= SAME_SLOT_CAP:
			continue   # 同槽触顶，重滚
		slot_counts[pick.slot] = sc + 1
		result.append(pick)
		_pending_recruit_equip.append(pick.id)
	return result
```

- [ ] **Step 4: get_recruit_offers 停止滚装**

`get_recruit_offers()` 末尾删除滚装段（`_offer_equipment.clear()` 起至 `_offer_equipment[crew.id] = pick.id` 的整段循环），直接 `return offers`。

- [ ] **Step 5: confirm_recruit 加 equip_picks 参 + 删 get_offer_equipment**

`confirm_recruit` 改签名与装备装入逻辑：

```gdscript
# 选中候选加入 roster；equip_picks 为玩家选的 eid 数组（限不同槽，越界/同槽忽略）。→CHARTING。
func confirm_recruit(unit_id: String, equip_picks: Array = []) -> void:
	var def := UnitDataManager.get_unit(unit_id)
	if def is CrewDefinition:
		roster.append(def as CrewDefinition)
		var slots: Dictionary = {}
		for raw in equip_picks:
			var eid := str(raw)
			var edef := EquipmentDataManager.get_equipment(eid)
			if edef == null:
				continue
			if slots.has(edef.slot):
				push_error("RunManager.confirm_recruit: 两件装备同槽，忽略第二件 — %s" % eid)
				continue
			slots[edef.slot] = eid
		if not slots.is_empty():
			_roster_equipment[unit_id] = slots
	else:
		push_error("RunManager.confirm_recruit: unit_id 非 CrewDefinition 或不存在 — %s" % unit_id)
	for offered_id in _last_offers:
		if offered_id != unit_id and not _excluded_offers.has(offered_id):
			_excluded_offers.append(offered_id)
	_last_offers.clear()
	_pending_recruit_equip.clear()
	_set_run_phase(RunPhase.RUN_CHARTING)
```

删除 `get_offer_equipment` 整个方法。

- [ ] **Step 6: 改写 run_equipment_test.gd 旧断言**

移除 `tests/unit/run_equipment/run_equipment_test.gd` 中所有 `get_offer_equipment` / `_offer_equipment` 断言；加 confirm_recruit picks 断言：

```gdscript
func test_confirm_recruit_assigns_two_picks_to_slots() -> void:
	var rm := RunManager
	rm._autosave_enabled = false
	rm.start_run()
	var offers := rm.get_recruit_offers()
	var crew_id := offers[0].id
	# 选两件不同槽：弯刀(主武器) + 板甲(护甲)
	rm.confirm_recruit(crew_id, ["eq_cutlass", "eq_plate"])
	var slots := rm.get_equipment_for(crew_id)
	assert_int(slots.size()).is_equal(2)
	assert_str(slots[EquipmentDefinition.Slot.MAIN_WEAPON].id).is_equal("eq_cutlass")
	assert_str(slots[EquipmentDefinition.Slot.ARMOR].id).is_equal("eq_plate")

func test_confirm_recruit_same_slot_keeps_first_only() -> void:
	var rm := RunManager
	rm._autosave_enabled = false
	rm.start_run()
	var offers := rm.get_recruit_offers()
	var crew_id := offers[0].id
	# 两件同为主武器：仅第一件生效
	rm.confirm_recruit(crew_id, ["eq_cutlass", "eq_sabre"])
	var slots := rm.get_equipment_for(crew_id)
	assert_int(slots.size()).is_equal(1)
	assert_str(slots[EquipmentDefinition.Slot.MAIN_WEAPON].id).is_equal("eq_cutlass")
```

- [ ] **Step 7: 跑测试确认通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_equipment`
Expected: PASS。

- [ ] **Step 8: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_equipment/
git commit -m "feat(recruit): roll-8-pick-2 weighted equipment acquisition (2a)

Story: equipment-slots-rarity-foundation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: RouteScene 招募「滚 8 选 2」白盒 UI（ADVISORY）

**Files:**
- Modify: `src/ui/route_scene.gd`（`_show_recruit_offers`、`_on_recruit_chosen`、新增 `_show_equip_picks`、`_equipment_summary` 加品阶标签）
- Test: `tests/integration/equipment_recruit_ui/equipment_recruit_ui_test.gd`（改写为 pick-2 流程的逻辑断言）

**Interfaces:**
- Consumes: Task 4 的 `roll_recruit_equipment()`、`confirm_recruit(unit_id, equip_picks)`

- [ ] **Step 1: 改写招募 UI 流程**

`src/ui/route_scene.gd`：`_show_recruit_offers` 去掉每张卡的 `get_offer_equipment`（卡只显示船员），`_on_recruit_chosen` 改为进入选装页：

```gdscript
func _show_recruit_offers() -> void:
	var offers := RunManager.get_recruit_offers()
	if offers.is_empty():
		_enter_deploy()
		return
	_clear_ui()
	_active_screen = "recruit"
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	add_child(box)
	var title := Label.new()
	title.text = "选择一名船员加入"
	box.add_child(title)
	for o in offers:
		var crew := o as CrewDefinition
		var btn := Button.new()
		btn.text = "%s · %s · %s" % [crew.unit_class, crew.display_name, crew.battle_cry]
		btn.pressed.connect(_on_recruit_chosen.bind(crew.id))
		box.add_child(btn)

func _on_recruit_chosen(unit_id: String) -> void:
	_show_equip_picks(unit_id)

# 滚 8 选 2 白盒页：8 件 toggle，最多选 2 且不同槽，确认装上 → 选航。
func _show_equip_picks(unit_id: String) -> void:
	_clear_ui()
	_active_screen = "equip_picks"
	var rolled := RunManager.roll_recruit_equipment()
	var selected: Array[String] = []        # 选中 eid
	var selected_slots: Dictionary = {}      # slot → true
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	add_child(box)
	var title := Label.new()
	title.text = "为新船员选择 2 件装备（已选 0/2）"
	box.add_child(title)
	var confirm := Button.new()
	confirm.text = "确认装备"
	confirm.disabled = true
	var toggles: Array[Button] = []
	for eq in rolled:
		var b := Button.new()
		b.toggle_mode = true
		b.text = _equipment_summary(eq)
		b.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				if selected.size() >= 2 or selected_slots.has(eq.slot):
					b.set_pressed_no_signal(false)   # 满 2 或同槽：禁选
					return
				selected.append(eq.id)
				selected_slots[eq.slot] = true
			else:
				selected.erase(eq.id)
				selected_slots.erase(eq.slot)
			title.text = "为新船员选择 2 件装备（已选 %d/2）" % selected.size()
			confirm.disabled = selected.size() == 0
		)
		toggles.append(b)
		box.add_child(b)
	confirm.pressed.connect(func() -> void:
		RunManager.confirm_recruit(unit_id, selected)
		_show_route_offers()
	)
	box.add_child(confirm)
```

`_equipment_summary` 前加品阶标签：

```gdscript
const _RARITY_LABELS := ["普通", "稀有", "史诗", "稀世", "传奇"]

func _equipment_summary(eq: EquipmentDefinition) -> String:
	var parts: Array[String] = []
	if eq.hp_bonus != 0: parts.append("%+d血" % eq.hp_bonus)
	if eq.damage_bonus != 0: parts.append("%+d攻" % eq.damage_bonus)
	if eq.range_bonus != 0: parts.append("%+d射程" % eq.range_bonus)
	if eq.move_bonus != 0: parts.append("%+d移动" % eq.move_bonus)
	var rlabel: String = _RARITY_LABELS[clampi(eq.rarity, 0, 4)]
	return "%s（%s）%s" % [eq.display_name, rlabel, " ".join(parts)]
```

> 确认 `_clear_ui()` 存在（route_scene.gd:42）并在新分支正确清屏。

- [ ] **Step 2: 改写招募 UI 集成测试**

`tests/integration/equipment_recruit_ui/equipment_recruit_ui_test.gd` 改为驱动 RunManager 的逻辑断言（不渲染节点）：

```gdscript
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._rng.seed = 42

func test_roll_then_confirm_two_picks_equips_crew() -> void:
	var rm := RunManager
	rm.start_run()
	var offers := rm.get_recruit_offers()
	var crew_id := offers[0].id
	var rolled := rm.roll_recruit_equipment()
	assert_int(rolled.size()).is_equal(8)
	# 模拟 UI 选 2 件不同槽
	var picks: Array[String] = []
	var seen_slots: Dictionary = {}
	for eq in rolled:
		if seen_slots.has(eq.slot): continue
		seen_slots[eq.slot] = true
		picks.append(eq.id)
		if picks.size() == 2: break
	rm.confirm_recruit(crew_id, picks)
	assert_int(rm.get_equipment_for(crew_id).size()).is_equal(2)
	assert_str(rm.current_phase).is_equal("CHARTING")
```

- [ ] **Step 3: 跑测试确认通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/equipment_recruit_ui`
Expected: PASS。

- [ ] **Step 4: 提交**

```bash
git add src/ui/route_scene.gd tests/integration/equipment_recruit_ui/
git commit -m "feat(ui): recruit roll-8-pick-2 whitebox screen (2a)

Story: equipment-slots-rarity-foundation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 端到端集成（AC-7）+ 全量回归修复

**Files:**
- Test: `tests/integration/equipment_slots/equipment_slots_e2e_test.gd`（create）
- Modify: 任何因新招募签名/流程而失败的既有集成测试（`tests/integration/chart_course/full_route_test.gd`、`tests/integration/run_loop/run_loop_test.gd`、`tests/integration/bounty/bounty_test.gd` 等）

**Interfaces:**
- Consumes: Task 1-5 全部

- [ ] **Step 1: 写端到端测试（失败/红前先确认覆盖）**

创建 `tests/integration/equipment_slots/equipment_slots_e2e_test.gd`：

```gdscript
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._rng.seed = 99

func test_recruit_two_slots_reflect_in_battle_effective_values() -> void:
	var rm := RunManager
	rm.start_run()
	var offers := rm.get_recruit_offers()
	var crew_id := offers[0].id
	# 选弯刀(+1攻,主武器) + 板甲(+3血,护甲)
	rm.confirm_recruit(crew_id, ["eq_cutlass", "eq_plate"])
	var crew_def := UnitDataManager.get_unit(crew_id)
	var slots := rm.get_equipment_for(crew_id)
	var inst := UnitInstance.from_definition(crew_def, slots)
	assert_int(inst.get_base_damage()).is_equal(crew_def.base_damage + 1)
	assert_int(inst.get_max_hp()).is_equal(crew_def.max_hp + 3)
```

- [ ] **Step 2: 跑该测试确认通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/equipment_slots`
Expected: PASS。

- [ ] **Step 3: 跑全量回归，修复残留**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
修复任何残留失败：
- `confirm_recruit(unit_id)`（无 picks）调用仍合法（默认 `[]`），断言 roster/phase 不变即可；若旧测试断言 roster_equipment 单件格式 → 改为 `get_equipment_for(...).size()`。
- 复原 Task 3 Step 11 中临时注释的 TODO(Task4) 断言（现 `get_offer_equipment` 已删，应删除对应旧断言而非复原）。
Expected: 全量 PASS（基线 387 + 本 epic 新增测试，导入零错误）。

- [ ] **Step 4: 提交**

```bash
git add tests/
git commit -m "test(equipment): e2e slot bonuses in battle + regression fixes (2a)

Story: equipment-slots-rarity-foundation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage（对照 ②a spec §8 验收标准）：**
- AC-1（字段 + 31 件 + 校验）→ Task 1 + Task 2 ✓
- AC-2（rarity/slot 过滤查询）→ Task 1 ✓
- AC-3（多槽求和钳零）→ Task 3 ✓
- AC-4（滚 8 加权 + 同槽≤2 + 选 2 不同槽 + 确定性）→ Task 4 ✓
- AC-5（get_equipment_for 字典 + 部署反映）→ Task 3 + Task 6 ✓
- AC-6（存档嵌套 + 旧档迁移 + 双过滤）→ Task 3 ✓
- AC-7（端到端集成）→ Task 6 ✓
- AC-8（31 件导入 smoke）→ Task 2 ✓
- AC-9（招募滚 8 选 2 UI，ADVISORY）→ Task 5 ✓

**Placeholder scan：** 无 TODO/TBD（Task 3 Step 11 的 TODO(Task4) 是显式临时标记，Task 6 Step 3 明确复原/删除）。所有代码步给出完整代码。

**Type consistency：** `from_definition(def, equipment:Dictionary={})`、`get_equipment_for(...)->Dictionary`、`_roster_equipment: crew_id→{slot:eid}`、`confirm_recruit(unit_id, equip_picks:Array=[])`、`roll_recruit_equipment()->Array[EquipmentDefinition]`、`Slot`/`Rarity` 枚举——跨任务一致。`_pending_recruit_equip: Array[String]` 仅 Task 4/5 内部用。

**风险提示：** `eq.get(field)` 依赖 Resource 动态属性访问（Godot 支持）；若 `--import` 后类名缓存异常，回退为显式字段求和。
