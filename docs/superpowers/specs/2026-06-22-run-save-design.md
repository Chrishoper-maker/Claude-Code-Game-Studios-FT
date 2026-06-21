# 通用存档（进行中 run）设计

> **Status**: Approved（用户确认 2026-06-22）
> **Author**: Chris + Claude Code
> **Date**: 2026-06-22
> **System**: #13 存档系统（systems-index：Persistence / Alpha）
> **依赖**: 航线与招募（run 状态源）；与悬赏成长 MetaProgress 并列但**独立存储**

## Overview

游戏现无进行中 run 的存档：关掉就从头再来。本增量交付**进行中 run 的存读档层**——在战斗间隙的航点自动存档到 `user://run.json`，提供 `load_run/has_save/delete_save` API 供未来主菜单"继续上次航程"消费；一局结束（出航成功/全灭）删档。**不含**战斗中存档（退出则该岛重打）、主菜单"继续"按钮接线（你以后改菜单时 3 行接上）。MetaProgress（解锁集）独立、不并入本存档。

## Player Fantasy

中途有事关掉游戏，下次回来还能从上一个航点接着打这趟航程——长局肉鸽不必一次坐到底。

## Detailed Rules

### Rule 1：RunManager 序列化（纯，可单测）

`to_save_dict() -> Dictionary` 序列化进行中 run 状态：

| 键 | 值 |
|----|----|
| `version` | int = 1 |
| `phase` | `current_phase`（String 门面） |
| `island_index` | `current_island_index` |
| `last_run_won` | bool |
| `roster` | roster 各 `CrewDefinition.id`（Array[String]） |
| `pending_deploy` | pending_deploy 各 id（Array[String]） |
| `downed_this_run` | `_downed_this_run` 副本 |
| `downed_pending_notice` | `_downed_pending_notice` 副本 |
| `excluded_offers` | `_excluded_offers` 副本 |
| `last_offers` | `_last_offers` 副本 |
| `rng_state` | `str(_rng.state)`（String，防 JSON 大整数精度丢失） |

`load_from_save_dict(d: Dictionary) -> void` 逆向恢复：
- `current_island_index = int(d.get("island_index", -1))`；`last_run_won = bool(d.get("last_run_won", false))`。
- `roster` / `pending_deploy`：清空后遍历 id 数组，`UnitDataManager.get_unit(id)` 解析，`is CrewDefinition` 才 append（缺失 id 防御性跳过）。
- 四个 String 集合：清空后 `str()` 逐元素归一恢复。
- `phase`：String → RunPhase 枚举，**直接赋 `_phase`**（不经 `_set_run_phase`，避免 load 时发 `run_phase_changed` 信号 / 触发自动存档）；未知串退化 `RUN_IDLE`。
- `rng_state`：`_rng.state = int(d.get("rng_state", "0"))`。

### Rule 2：持久化文件层

- `var _save_path: String = "user://run.json"`（测试可注入临时路径）。
- `save_run()`：`FileAccess.open(_save_path, WRITE)`，写 `JSON.stringify(to_save_dict())`；打开失败 `push_error` 不致命。
- `load_run()`：文件不存在 → 直接返回（不改状态）；存在则读 + `JSON.parse_string`，结果为 Dictionary → `load_from_save_dict`；解析失败 → `push_error` 返回（不改状态）。
- `has_save() -> bool`：`FileAccess.file_exists(_save_path)`。
- `delete_save()`：存在则 `DirAccess.remove_absolute(_save_path)`。

### Rule 3：航点自动存档钩子

- `var _autosave_enabled: bool = true`。
- `_on_run_phase_entered(phase)`：`if _autosave_enabled`——进入 `RUN_DEPLOYING` / `RUN_RECRUITING` → `save_run()`；进入 `RUN_END` → `delete_save()`；`RUN_ISLAND_BATTLE` / `RUN_IDLE` 不动。
- 战斗（BATTLE）不存 → 战斗中退出，存档停在进入战斗前的航点（DEPLOYING/RECRUITING）。

### Rule 4：测试隔离（既有套件）

自动存档使任何驱动 RunManager 阶段转换的测试都会写文件。既有驱动 RunManager 阶段的套件在 `before_test` 加 `RunManager._autosave_enabled = false`（约 8 个：run_manager / run_loop / deploy_screen / downed_notice / run_end / bounty / permadeath / full_battle）。存档自身的测试套件显式开启 + 注入临时 `_save_path` + 清理。

## Formulas

无数值公式。岛序恢复对齐：DEPLOYING 存档时 `island_index` 尚未自增（`confirm_deploy` 才 +1），故"继续"恢复 DEPLOYING → `confirm_deploy` → 进入正确的该岛战斗（与首航 index=-1→0 同一逻辑）。

## Edge Cases

- **战斗中退出**：最近存档为该岛的 DEPLOYING/RECRUITING 航点 → 恢复后重打该岛（损失当场战斗进度）。
- **终局后**：`RUN_END` 删档 → `has_save()` 假 → 无可继续。
- **无存档文件**：`load_run()` 不改状态；`has_save()` 假。
- **存档损坏/解析失败**：`load_run()` `push_error` 返回，不改当前状态（不崩、不清空进行中内存状态）。
- **存档里的 crew id 已不存在**（数据变更）：`load_from_save_dict` 跳过该 id（roster 少一人，不崩）。
- **rng_state 缺失/非法**：`int(...)` 退化 0；招募序列仅失去跨档一致性，不崩。
- **load 不发信号**：直接赋 `_phase`，不触发 `run_phase_changed` / 自动存 → 不产生递归存档或 UI 误响应。
- **测试隔离**：`_autosave_enabled=false`（既有套件）或临时 `_save_path`（存档套件）→ 不写真实 `user://run.json`。

## Dependencies

| 系统 | 接口 | 说明 |
|------|------|------|
| RunManager 自身 | 全部 run 状态字段 | 序列化/恢复源 |
| UnitDataManager | `get_unit(id)` | id→CrewDefinition 解析 |
| 文件系统 | `FileAccess`/`JSON`/`DirAccess`/`user://run.json` | 持久化 |
| （未来）MainMenu | `has_save()`/`load_run()` + `SceneManager.goto_route()` | "继续"消费（本增量不接线） |

不改：MetaProgress、SceneManager、RouteScene、战斗层。MainMenu 不动。

## Tuning Knobs

| 项 | 默认 | 说明 |
|----|------|------|
| 存档路径 | `user://run.json` | `RunManager._save_path` |
| 自动存档开关 | true | `RunManager._autosave_enabled`（测试关） |
| 存档版本 | 1 | `to_save_dict.version`（未来迁移判别） |

## Acceptance Criteria

**AC-1：to_save_dict/load_from_save_dict 往返**【单元】构造 run 状态（roster/island/phase/downed/excluded/rng）→ `to_save_dict` → 改乱内存 → `load_from_save_dict(dict)` → 各字段恢复一致（roster id 序列、island_index、current_phase、_downed_this_run、_excluded_offers）。

**AC-2：load 跳过缺失 id**【单元】dict.roster 含一个不存在 id + 合法 id → `load_from_save_dict` → roster 仅含合法者，不崩。

**AC-3：load 不发 run_phase_changed**【单元】监听 EventBus.run_phase_changed → `load_from_save_dict({phase:"RECRUITING",...})` → 信号未发；`current_phase=="RECRUITING"`。

**AC-4：save_run→load_run 文件往返**【集成】临时 `_save_path` → 设状态 → `save_run()` → `has_save()` 真 → 改乱 → `load_run()` → 状态恢复（用临时文件，测后删）。

**AC-5：has_save / delete_save**【集成】无文件 `has_save` 假；`save_run` 后真；`delete_save` 后假。

**AC-6：load_run 缺/坏文件不改状态**【集成】无文件时 `load_run()` 后内存状态不变；写入非 JSON 文本后 `load_run()` 不崩、状态不变。

**AC-7：航点自动存**【集成】`_autosave_enabled=true` + 临时路径 → 进入 DEPLOYING（start_run）或 RECRUITING → `has_save()` 真；进入 RUN_END → `has_save()` 假。

**AC-8：autosave 关闭时不写**【集成】`_autosave_enabled=false` + 确保无文件 → start_run（进 DEPLOYING）→ `has_save()` 仍假。

**AC-9：全量回归绿**（既有套件加 `_autosave_enabled=false` 隔离后）。

## 范围/偏离

1. 仅存读档层 + 航点自动存/终局删档；**主菜单"继续"按钮接线延后**（你改菜单时接上；API 已就绪）。
2. **不做战斗中存档**（退出重打该岛）。
3. run.json 与 MetaProgress 的 meta.json 分离（per-run vs 跨-run）。
4. `load_from_save_dict` 直接赋 `_phase` 不发信号（与正常转换刻意不同，避免 load 副作用）——已记理由。
