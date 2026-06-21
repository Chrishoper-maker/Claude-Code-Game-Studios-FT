# 船员永久死亡（Crew Permadeath）设计

> **Status**: Approved（自主推进，用户授权"用推荐项自行决策"2026-06-21）
> **Author**: Chris（授权）+ Claude Code
> **Date**: 2026-06-21
> **Epic**: route-recruitment（C 元层 / 跨战斗机制）
> **GDD 来源**: route-recruitment-system（_downed_this_run / R1 排除）、route-recruitment-ui（阵亡通知卡，本 spec 不含 UI）

## Overview

当前战斗中单位被击倒只发 `unit_downed(battle_id:int)`（驱动胜负判定与视觉）。`crew_member_downed` 信号已声明但**全代码库无人发射**；`RunManager._downed_this_run` 是 `Array[int]`、只被写无人读，且 battle_id 每战重新分配、跨战无意义——半成品。结果：阵亡的我方船员战后**仍留在 roster**，下一岛还能部署，"可感知的损失"情感承诺缺失。

本增量实现**核心永久死亡**：我方船员在战斗中被击倒 → 战后永久移出 roster（本 run 不再可部署、不再被招募），并记录用于将来阵亡通知卡。**不含** UI（阵亡通知卡留后续）。

## Player Fantasy

死亡是 run 故事的一部分，而非纯粹失分。带 5 个人出航、第 3 岛折了铁壁——下一岛真的少一个人，玩家感到"这条命没了"。损失可感知、有重量。

## Detailed Rules

### Rule 1：`crew_member_downed` 改为携带持久 String id

`EventBus.crew_member_downed` 签名由 `(unit_id: int)` 改为 `(crew_id: String)`——传**持久船员身份**（roster `CrewDefinition.id`），而非每战重分配的 battle_id。该信号此前无发射方、唯一消费方是 `RunManager._on_crew_member_downed`，改签名安全。

### Rule 2：BattleScene 桥接 unit_downed → crew_member_downed

`BattleScene._ready` 新增订阅 `EventBus.unit_downed`：

```
func _relay_crew_downed(battle_id: int) -> void:
	var inst := _turn_manager.get_unit(battle_id)
	if inst != null and inst.definition.faction == "crew":
		EventBus.crew_member_downed.emit(inst.get_unit_id())
```

仅我方（`faction == "crew"`）转发；敌方击倒不触发。`get_unit_id()` 返回 `definition.id`（持久 String）。战斗场景是 battle↔meta 桥（经 autoload 通信，ADR-0002），故桥接置于此。

### Rule 3：RunManager 永久移除

`RunManager._on_crew_member_downed(crew_id: String)`：
1. 已在 `_downed_this_run` → 直接返回（去重）。
2. 记入 `_downed_this_run`（类型改为 `Array[String]`）。
3. 从 `roster` 移除 `id == crew_id` 的 `CrewDefinition`（倒序遍历 remove_at，防索引漂移）。
4. 加入 `_excluded_offers`（本 run 不再招募——死者不复活）。

移除**即时**（战斗中收到即移），安全：roster 是元层名单，战斗用 pending_deploy/TurnManager 的 battlefield，胜负判定走 `get_alive_*`（battlefield，非 roster）——移除 roster 不影响进行中的战斗。

## Formulas

无数值公式（纯状态机/集合操作）。

## Edge Cases

- **同一船员重复 unit_downed**：Rule 3 步骤 1 去重，roster 只移一次。
- **敌方单位被击倒**：Rule 2 faction 过滤，不发 crew_member_downed。
- **get_unit(battle_id) 返回 null**（理论越界）：Rule 2 null 守卫，跳过。
- **战败同回合多名 crew 阵亡**：各自一次 unit_downed → 各自转发 → 各自移除；run 仍因 battlefield 全灭走 battle_lost。
- **移除后 run_completed 快照**：`_on_battle_lost` 的 `roster.duplicate()` 反映移除后的 roster（少了刚阵亡者）。当前 run-end UI 只显示"全员阵亡"文案、不列名单，故无影响。
- **start_run 复位**：已 `roster.clear()` + `_downed_this_run.clear()` + `_excluded_offers.clear()`，新 run 干净（`_downed_this_run` 改类型不影响 clear）。
- **阵亡者是 starting tier**：同样移除；不影响 `_excluded_offers`（starting 本就不在 pool offer 池，加入无害）。

## Dependencies

| 系统 | 接口/信号 | 方向 | 说明 |
|------|----------|------|------|
| BattleResolution (#4) | `EventBus.unit_downed(battle_id)` | 接收 | 既有发射方（resolve_unit_downed 步骤 7） |
| TurnManager (#3) | `get_unit(battle_id) -> UnitInstance` | 调用 | battle_id→实例→`get_unit_id()`/faction |
| RunManager (#11) | `crew_member_downed(crew_id)` / `roster` / `_excluded_offers` / `_downed_this_run` | 发射+改 | 永久移除 + 防复活 |
| 阵亡通知 UI（route-recruitment-ui） | `_downed_this_run`（String） | （未来）| 战后汇总阵亡卡读此集合；本 spec 仅备好数据 |

**不改**：unit_downed 发射逻辑、胜负判定、视觉（UnitRenderer/DamageFloater 仍按 battle_id 工作）。

## Tuning Knobs

无（永久死亡是布尔机制，无可调值）。

## Acceptance Criteria

**AC-1：crew_member_downed 移除 roster 对应船员**【单元】
- Given: roster 含 id="crew_swordsman_01" 等
- When: `RunManager._on_crew_member_downed("crew_swordsman_01")`
- Then: roster 不再含该 id；`_downed_this_run` 含该 id；`_excluded_offers` 含该 id

**AC-2：重复阵亡去重**【单元】
- Given: 已对 "crew_swordsman_01" 调用一次
- When: 再次 `_on_crew_member_downed("crew_swordsman_01")`
- Then: `_downed_this_run` 仍只 1 条；roster 不二次报错

**AC-3：阵亡者不再被招募**【单元】
- Given: 某 pool 船员 id 经 `_on_crew_member_downed` 标记
- When: `get_recruit_offers()`（清其余排除以便观察）
- Then: offers 不含该 id

**AC-4：BattleScene 桥接——我方击倒发 crew_member_downed 并移出 roster**【集成】
- Given: start_run + confirm_deploy(起始编制) + 实例化 BattleScene（部署 2 crew）
- When: `_battle_resolution.resolve_unit_downed(<某 crew battle_id>)`
- Then: 触发 crew_member_downed → roster 移除该 crew（size 减 1，该 id 不在 roster）

**AC-5：敌方击倒不影响 roster**【集成】
- Given: 同上 BattleScene（4 敌 + 2 crew）
- When: resolve_unit_downed(<某 enemy battle_id>)
- Then: roster 不变（无 crew_member_downed）

**AC-6：不破既有回归**【全量】
- 全量套件保持绿（run_loop/deploy_screen/full_battle 等），signal 改签名后相关测试更新。

## 偏离/范围说明

1. **crew_member_downed 改签名（int→String）**：原 int 语义半成品（battle_id 跨战无意义、无发射方），String 持久 id 才能跨战移除 roster。
2. **即时移除而非战后批量**：roster 与 battlefield 解耦，即时移除最简且无副作用。
3. **不含阵亡通知卡 UI**：留 route-recruitment-ui story；本 spec 备好 `_downed_this_run`（String）数据。
4. **桥接置于 BattleScene** 而非新建节点：BattleScene 已是 battle↔meta 编排器（连 battle_started/won/lost）；YAGNI 不新建专用节点。
