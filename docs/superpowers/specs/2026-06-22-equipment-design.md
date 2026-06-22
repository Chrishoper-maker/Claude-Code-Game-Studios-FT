# 装备系统（MVP·纯数值·招募卡携带）设计

> Story: equipment (#15) · 2026-06-22 · 引擎 Godot 4.6.3 / GDScript / GdUnit4

## 1. Overview

为每名通过招募获得的船员附带一件随机装备，装备纯粹修改四项现有数值
（`max_hp / base_damage / attack_range / move_range`）。装备绑定到携带它的
船员，随该船员存在于本 run 期间；船员阵亡或 run 终局即随之消失（run 作用域，
不跨 run 持久）。本期 MVP **只做数值强化**，不含触发效果、不新增技能动词、
不新增 run 阶段或获取 UI——完全寄生于现有招募三选一流程。

## 2. Player Fantasy

每次招募不只是"多一个人"，而是"这个人带着什么宝贝"。同一职业因装备不同
而产生 build 差异（如带板甲的剑豪更肉、带望远镜的炮手打更远），让招募抉择
更有取舍。

## 3. Detailed Rules

### Rule 1 — 装备数据模型
- `EquipmentDefinition`（Resource，`class_name EquipmentDefinition`）字段：
  - `id: String`、`display_name: String`
  - `hp_bonus: int`、`damage_bonus: int`、`range_bonus: int`、`move_bonus: int`
  - 四项增量默认 0；可正可负（MVP 数据只用非负，但模型不限制）。
- 装备 .tres 存于 `assets/data/equipment/`，由 `EquipmentDataManager` 自动扫描。

### Rule 2 — 装备数据管理器（autoload）
- `EquipmentDataManager`（autoload，**不声明 class_name**，沿用 UnitDataManager 约束）。
  - 启动扫描 `assets/data/equipment/*.tres`，缓存 id→EquipmentDefinition。
  - `get_equipment(id: String) -> EquipmentDefinition`（缺失返回 null）。
  - `get_all_equipment() -> Array[EquipmentDefinition]`。
  - `is_loaded` 标志（仿现有 DataManager）。
- 注册进 `project.godot [autoload]`，置于 RunManager 之前（RunManager 招募滚装备时依赖它）。

### Rule 3 — 起始装备池（4 件 .tres）
| id | display_name | 增量 |
|----|----|----|
| `eq_cutlass` | 弯刀 | damage_bonus +1 |
| `eq_plate` | 板甲 | hp_bonus +3 |
| `eq_spyglass` | 望远镜 | range_bonus +1 |
| `eq_boots` | 轻靴 | move_bonus +1 |

### Rule 4 — UnitInstance 有效值（方案 A）
- `UnitInstance` 新增字段 `equipment: EquipmentDefinition = null`。
- `from_definition(def: UnitDefinition, equipment: EquipmentDefinition = null) -> UnitInstance`：
  设 `inst.equipment = equipment`，**初始 `current_hp = inst.get_max_hp()`**（含装备血量）。
- 新增四个有效值访问器（基值 + 装备增量；equipment 为 null 时取 0 增量）：
  - `get_max_hp() -> int`         = `definition.max_hp + (equipment ? equipment.hp_bonus : 0)`
  - `get_base_damage() -> int`    = `definition.base_damage + (equipment ? equipment.damage_bonus : 0)`
  - `get_attack_range() -> int`   = `definition.attack_range + (equipment ? equipment.range_bonus : 0)`
  - `get_move_range() -> int`     = `definition.move_range + (equipment ? equipment.move_bonus : 0)`
- 有效值下限钳 0（防负装备把数值压到负；`maxi(0, ...)`）。
- `definition` 仍为共享只读模板（不克隆、不写回，符合 ADR-0003 既有契约）。

### Rule 5 — 战斗读值切换
将所有战斗逻辑里对这四项的读取从 `unit.definition.X` 改为 `unit.get_X()`。
已知约 15 处，分布于：`battle_resolution.gd`、`battle_scene.gd`、
`player_turn_controller.gd`、`battle_hud.gd`、`enemy_ai.gd`。敌方 UnitInstance
的 equipment 恒为 null → 有效值等于基值，行为不变。

### Rule 6 — RunManager 装备账本
- 新字段：
  - `_roster_equipment: Dictionary`（crew_id → equipment_id），已招募船员的装备绑定。
  - `_offer_equipment: Dictionary`（crew_id → equipment_id），当前招募批次每个候选滚到的装备。
- `get_recruit_offers()`：在选出 ≤3 候选后，为每名候选用持有的 `_rng` 从
  `EquipmentDataManager.get_all_equipment()` 随机滚一件，写入 `_offer_equipment`
  （先 `clear()`）。滚动顺序确定性（按 offer 顺序、`_rng.randi_range`），供存档
  rng_state 复现。装备池为空时不滚（候选无装备）。
- `get_offer_equipment(crew_id: String) -> EquipmentDefinition`（缺失返回 null），供招募卡 UI。
- `confirm_recruit(unit_id)`：在现有逻辑基础上，
  `_roster_equipment[unit_id] = _offer_equipment.get(unit_id, "")`（空串表示无装备），
  然后 `_offer_equipment.clear()`。
- `get_equipment_for(crew_id: String) -> EquipmentDefinition`：查 `_roster_equipment`
  → EquipmentDataManager；无记录或空串或缺失定义 → null。
- **起始船员不带装备**（`start_run` 填编制时不写 `_roster_equipment`）。
- permadeath `_on_crew_member_downed(crew_id)`：现有逻辑基础上 `_roster_equipment.erase(crew_id)`。

### Rule 7 — 部署落地
- `BattleMap.deploy_crew(crew_defs: Array, positions: Array, equipments: Array = []) -> bool`：
  新增并行 `equipments` 参数（与 crew_defs 同序，缺省空数组=全 null）；
  `UnitInstance.from_definition(crew_defs[i], equipments[i] if i < equipments.size() else null)`。
- `battle_scene.gd _deploy_run_crew()`：构造 `equipments` 时按 `RunManager.get_equipment_for(def.id)` 取。
- `battle_scene.gd _spawn_all_views()`：`set_unit_max_hp` 与 `view.set_hp` 改用 `inst.get_max_hp()`。

### Rule 8 — 招募卡 UI
RouteScene RECRUITING 分支：每张候选卡文字追加装备名 + 加成摘要
（如 `弯刀 +1攻` / `板甲 +3血` / `望远镜 +1射程` / `轻靴 +1移动`；无装备则不追加）。
白盒标签，仅文字。加成摘要由装备四项非零增量拼成（中文短标签：攻/血/射程/移动）。

### Rule 9 — 存档
- `to_save_dict()` 新增键 `"roster_equipment"`（Dictionary crew_id→equipment_id 的副本）。
- `load_from_save_dict(d)`：恢复 `_roster_equipment`，仅保留其 crew_id 仍在 roster、
  且 equipment_id 在 EquipmentDataManager 有定义的条目（缺失优雅跳过=该船员无装备）。
- `_offer_equipment` **不存**（resume 落在航点 phase，offer 由 RouteScene 重新生成，
  借存档恢复的 rng_state 复现同样的候选与装备）。

## 4. Formulas

- 有效值：`effective_X = maxi(0, definition.base_X + (equipment ? equipment.X_bonus : 0))`。
- 初始血量：`current_hp = get_max_hp()`（部署/战斗开始时）。
- 招募装备滚动：对每个候选 `i`，`equip = pool[_rng.randi_range(0, pool.size()-1)]`（有放回；
  允许同批多候选滚到同款，MVP 不去重）。

## 5. Edge Cases

- **装备池为空**：`get_recruit_offers` 不滚，候选与已招船员均无装备；`get_equipment_for` 返 null；不崩。
- **load 缺失 equipment id**：视为该船员无装备（跳过该条目）。
- **load crew_id 不在 roster**：丢弃该 equipment 条目（与 roster 一致性）。
- **敌方单位**：equipment 恒 null，有效值=基值。
- **起始船员**：无装备。
- **每船员一件、不叠加**：`_roster_equipment` 单值映射。
- **负增量压到负数**：有效值钳 0（防御，MVP 数据不触发）。
- **permadeath**：船员移出 roster 时同步擦除其装备绑定。

## 6. Dependencies

- `UnitDataManager`（招募池来源，既有）。
- `EquipmentDataManager`（新增 autoload）。
- `MetaProgress`（招募解锁判定，既有；与装备无耦合）。
- `RunManager._rng`（装备随机滚动 + 存档复现，既有）。
- 战斗系统（BattleResolution / PlayerTurnController / EnemyAI / BattleHUD / BattleScene / BattleMap）
  ——仅改数值读取来源，不改逻辑。

## 7. Tuning Knobs

- 4 件装备各自的四项增量数值（`assets/data/equipment/*.tres`）。
- 装备池构成（增删 .tres）。
- 是否允许同批候选滚到同款（当前：允许/有放回）。

## 8. Acceptance Criteria

- **AC-1**：EquipmentDataManager 扫描 `assets/data/equipment/` 后 `get_equipment("eq_plate")`
  返回 hp_bonus=3 的定义；`get_all_equipment().size() >= 4`。
- **AC-2**：`UnitInstance.from_definition(def, eq_plate)` 的 `get_max_hp()` = `def.max_hp + 3`，
  且初始 `current_hp` = `get_max_hp()`。
- **AC-3**：`from_definition(def)`（无装备）四个 get_X() 等于对应 definition 基值。
- **AC-4**：`get_recruit_offers()` 在固定 `_rng.seed` 下，`get_offer_equipment(候选id)` 结果确定可复现。
- **AC-5**：`confirm_recruit(id)` 后 `get_equipment_for(id)` 返回该候选招募时滚到的装备。
- **AC-6**：permadeath（`_on_crew_member_downed(id)`）后 `get_equipment_for(id)` 返回 null。
- **AC-7**：带 eq_plate 的船员经 deploy_crew 上场后，其 UnitInstance `get_max_hp()` = 基值+3，
  且战斗解算 `heal` 钳顶用的是有效 max_hp（受击/治疗以有效值为准）。
- **AC-8**：to_save_dict→load_from_save_dict 往返后 `_roster_equipment` 恢复；
  load 时缺失 equipment id 的条目被跳过、不崩。
- **AC-9**：RouteScene 招募卡文字包含候选的装备名与加成摘要（有装备时）。
- **AC-10**：全量回归绿、`godot --headless --import` 零错、零孤儿。

## 9. 非目标（YAGNI）

- 触发效果（反伤/回血/首击加伤）——后续故事。
- 新增/改写技能动词——后续故事。
- 装备库存 / 更换 / 卸下 UI——后续故事。
- 跨 run 持久装备、装备稀有度/品级、多装备槽、叠加——均不在本期。
