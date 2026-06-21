# 悬赏成长系统（Bounty Progression）设计

> **Status**: Approved（用户确认 2026-06-21）
> **Author**: Chris + Claude Code
> **Date**: 2026-06-21
> **System**: #14 悬赏成长系统（systems-index：Progression / Alpha）
> **GDD 锚点**: game-concept「通关解锁新船员类型进入招募池（meta 进度仅此一条，防范围蔓延）」；unit-data-system `recruit_pool_tier=unlockable`（悬赏成长解锁）

## Overview

本作唯一的 meta 进度线：**打赢一整局（末岛胜）解锁一名新船员类型**，被解锁的 `unlockable` 船员进入后续 run 的招募池。解锁状态**跨会话持久化**。当前一切从零——无 unlockable 数据、无持久化、无该系统代码。

本增量建立：跨 run 持久化的 `MetaProgress`（单一职责 autoload）、通关解锁触发、招募池纳入已解锁船员、3 名 unlockable 船员数据。**不含**：悬赏等级 UI、run-end 解锁提示卡、进行中 run 的存档（MetaProgress 只存解锁集）。

## Player Fantasy

胜利不止是本局的结束，更是"长线"的推进：打通一局，下次出航的招募池里多一个从未见过的怪人船员。成长在于**选项变宽**而非数值膨胀——"再来一局"有了跨局的理由。

## Detailed Rules

### Rule 1：MetaProgress autoload（跨 run 持久化解锁集）

新增 `src/autoloads/meta_progress.gd`（注册名 `MetaProgress`，autoload 脚本不声明 class_name）。状态与接口：
- `unlocked_crew_ids: Array[String]`——已解锁的 unlockable 船员 id。
- `var _save_path: String = "user://meta.json"`——存盘路径（测试可注入临时路径）。
- `get_unlock_order() -> Array[String]`——固定解锁顺序 = `UnitDataManager.get_all_units()` 中 `recruit_pool_tier=="unlockable"` 的 id 按字典序升序（确定性，不依赖扫描顺序）。
- `unlock_next() -> String`——遍历 `get_unlock_order()`，解锁第一个不在 `unlocked_crew_ids` 者：append + `save()` + 返回其 id；全部已解锁返回 `""`（无副作用、不写盘）。
- `is_unlocked(crew_id: String) -> bool`——`unlocked_crew_ids.has(crew_id)`。
- `to_dict() -> Dictionary`——`{"unlocked_crew_ids": unlocked_crew_ids.duplicate()}`（纯，无 I/O）。
- `from_dict(d: Dictionary) -> void`——读 `unlocked_crew_ids`（缺键→空数组；逐元素 String 化，类型安全）。
- `save() -> void`——`FileAccess.open(_save_path, WRITE)` 写 `JSON.stringify(to_dict())`；打开失败 `push_error` 不致命。
- `load() -> void`——文件不存在→`unlocked_crew_ids=[]` 返回；存在则读 + `JSON.parse`，成功且为 Dictionary → `from_dict`，解析失败 `push_error` + 置空。
- `_ready()`——调 `load()`（游戏启动即读盘）。

**为何独立 autoload**：解锁是跨 run 状态，绝不能进 RunManager（其 `start_run` 清空所有字段）。单一职责、独立可测。

### Rule 2：通关解锁触发

`RunManager._on_battle_won` 末岛胜利分支（`current_island_index + 1 >= ISLAND_COUNT_MAX`，已设 `last_run_won=true` 并发 `run_completed(true,…)`）末尾调用 `MetaProgress.unlock_next()`。非末岛胜利、战败、中途退出**不**解锁。

### Rule 3：招募池纳入已解锁 unlockable

`RunManager.get_recruit_offers` 的候选过滤由
`crew.recruit_pool_tier == "pool"`
改为
`crew.recruit_pool_tier == "pool" or (crew.recruit_pool_tier == "unlockable" and MetaProgress.is_unlocked(crew.id))`。
其余不变量（排除 `roster` 内、排除 `_excluded_offers` 内、职业互异、Fisher-Yates 无放回、≤RECRUIT_OFFER_COUNT）原样适用。未解锁的 unlockable 永不进 offer。

### Rule 4：3 名 unlockable 船员数据

新增 3 个 `recruit_pool_tier="unlockable"` 的 crew `.tres`（`assets/data/units/`，CrewDefinition，数值复用现有强度带）。推荐（spec 复审可调）：
- `crew_gunner_03`（unlockable，远程）
- `crew_medic_02`（unlockable，辅助）
- `crew_swordsman_04`（unlockable，近战）

字典序解锁顺序：`crew_gunner_03` → `crew_medic_02` → `crew_swordsman_04`。各 `id/display_name/unit_class/battle_cry/class_action_id` 齐备，数值对齐 unit-data 强度带。

## Formulas

无数值公式。解锁顺序 = unlockable id 字典序升序；`unlock_next` = 该序中首个未解锁者。

## Edge Cases

- **全部已解锁后再通关**：`unlock_next()` 返回 `""`，不写盘、不报错。
- **首次启动无存档文件**：`load()` 得空集，无 unlockable 进 offer。
- **存档损坏/解析失败**：`load()` `push_error` + 置空集（不崩，等价全新进度）。
- **存盘 I/O 失败**：`save()` `push_error`，本局继续（解锁在内存生效，下次启动可能丢失——非致命）。
- **解锁的 unlockable 与 pool 同池**：受职业互异/排除规则约束（如已解锁 gunner_03 但 roster 已有 gunner，则该次 draw 可能因职业冲突不出）。
- **测试隔离**：MetaProgress 单例 → 测试 before/after 重置 `unlocked_crew_ids=[]` + 还原 `_save_path`；写盘测试用临时路径并删除。
- **既有 offer 测试**：`run_manager_test` 原断言"offer 皆 pool tier"在 unlockable 解锁时不再成立 → 放宽为"pool 或已解锁 unlockable"，且 before_test 清空 MetaProgress 保确定。

## Dependencies

| 系统 | 接口 | 方向 | 说明 |
|------|------|------|------|
| UnitDataManager (#1) | `get_all_units()` / `get_unit(id)` | 调用 | 枚举 unlockable + 取定义 |
| RunManager (#11) | `_on_battle_won`（末岛）/ `get_recruit_offers` | 改 | 触发解锁 + 招募集成 |
| 文件系统 | `FileAccess` / `JSON` / `user://meta.json` | I/O | 跨会话持久化 |

**双向**：unit-data-system 标注 `unlockable` 清单由本系统消费（已记于该 GDD「悬赏成长 → unlockable 清单」）。

不改：DeployScreen/permadeath/通知卡/run-end 既有流程；RunManager 的 per-run 状态字段。

## Tuning Knobs

| 项 | 默认 | 说明 |
|----|------|------|
| 每次通关解锁数 | 1 | `unlock_next` 单解锁；如需多解锁循环调用 |
| unlockable 船员集 | 3（gunner_03/medic_02/swordsman_04）| 数据驱动；增删 .tres 即改解锁曲线 |
| 存盘路径 | `user://meta.json` | `MetaProgress._save_path` |

## Acceptance Criteria

**AC-1：unlock_next 按字典序逐个解锁**【单元】空解锁集 → `unlock_next()` 返回 id 列表首个、`is_unlocked` 为真；再调返回第二个；全解锁后返回 `""` 且集合大小不增。

**AC-2：to_dict/from_dict 往返**【单元】`unlocked_crew_ids=[a,b]` → `from_dict(to_dict())` 后集合等价。

**AC-3：save→load 文件往返**【集成】注入临时 `_save_path` → 解锁两名 → `save()` → 新建/重置实例 `load()` → `unlocked_crew_ids` 含那两名（用临时文件，测后删除）。

**AC-4：通关触发解锁**【集成】MetaProgress 空 → 构造末岛局（island_index=ISLAND_COUNT_MAX-1）发 `battle_won` → MetaProgress 解锁数 +1（= 顺序首个）。

**AC-5：未解锁的 unlockable 不进 offer；解锁后进**【集成】MetaProgress 空 → `get_recruit_offers()` 不含任一 unlockable id；解锁某 unlockable（且其职业不被 roster 占、清其他排除）→ 其可出现在 offer。

**AC-6：非末岛胜/战败不解锁**【集成】非末岛 `battle_won` 或 `battle_lost` → MetaProgress 解锁数不变。

**AC-7：全量回归绿**（含放宽后的 run_manager offer 断言）。

## 偏离/范围

1. **只解锁不展示**：无悬赏等级 UI、无 run-end"解锁了 X"提示卡（留后续 UI story；run-end 已显示总结）。
2. **MetaProgress 仅存解锁集**，非通用存档（进行中 run 不持久化——续跑是独立 story）。
3. **解锁绑"末岛胜"**：MVP 固定 5 岛，无悬赏等级分层；threat_tier 分层解锁留 Full Vision。
4. **3 名 unlockable 身份/数值**为推荐，复审可调；不引入新机制，复用现有职业与强度带。
