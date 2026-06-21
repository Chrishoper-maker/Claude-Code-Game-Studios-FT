# 阵亡通知卡（Downed Notice）设计

> **Status**: Approved（自主推进，用户授权"用推荐项自行决策"2026-06-21）
> **Author**: Chris（授权）+ Claude Code
> **Date**: 2026-06-21
> **Epic**: route-recruitment-ui（Rule 4 / AC-8 / AC-12）
> **前序**: crew-permadeath（备好 `_downed_this_run`；本 spec 加"本批待通知"集合）

## Overview

永久死亡已落地（阵亡 crew 移出 roster），但玩家在战后**得不到任何告知**——损失静默发生。本增量在 RouteScene 白盒中枢里，于战后进入招募/终局界面**之前**，先弹一张"阵亡通知卡"列出本场阵亡船员（"职业·名 在第 N 岛阵亡"），玩家点「继续」后再进入后续界面。白盒 UI，无美术（灰阶图标/衬线铭文等留正式美术）。

## Player Fantasy

死亡可感知、有仪式感：折了人，游戏郑重告诉你"谁、在哪一岛倒下"，而不是名单里悄悄少一个。损失是 run 故事的一部分。

## Detailed Rules

### Rule 1：RunManager 记录"本批待通知"

新增 `_downed_pending_notice: Array[String]`。`_on_crew_member_downed(crew_id)` 在去重通过后，除记 `_downed_this_run` 外，也 append 到 `_downed_pending_notice`。提供：
- `get_pending_downed_notice() -> Array[String]`（副本）
- `clear_downed_notice()`（清空 `_downed_pending_notice`）
`start_run()` 一并清空 `_downed_pending_notice`。

> 通知每场战后（每次 RECRUITING/RUN_END）展示并清空，故"待通知"集合内的阵亡都发生在 `current_island_index` 这一岛。

### Rule 2：RouteScene 通知门控

`_ready` 的 RECRUITING 与 RUN_END 分支改为：先经 `_notice_then(next: Callable)`：
- 若 `get_pending_downed_notice()` 非空 → `_show_downed_notice(next)`（展示通知卡，「继续」回调里 `clear_downed_notice()` + `_clear_ui()` + `next.call()`）。
- 否则 → 直接 `next.call()`。

IDLE/DEPLOYING 分支不过门控（起航/部署无战后通知）。

### Rule 3：通知卡内容（白盒）

`_show_downed_notice(next)` 渲染（先 add_child 再 set_anchors）：
- 标题 Label："折损通知"
- 每名阵亡 crew 一行 Label：`"%s · %s 在第 %d 岛阵亡" % [class, name, current_island_index + 1]`，class/name 经 `UnitDataManager.get_unit(id)`（数据静态，crew 虽出 roster 仍可查）。
- 「继续」Button（存 `_notice_continue_button`）：pressed → `clear_downed_notice()` + `_clear_ui()` + `next.call()`。

## Formulas

`岛号 = current_island_index + 1`（0-based→1-based 展示）。

## Edge Cases

- **无阵亡**：pending 空 → 跳过通知，直接进招募/终局（保 run_loop AC-2/AC-7 回归）。
- **多名同场阵亡**：多行 Label，一个「继续」一次清空全部。
- **get_unit(id) 返回非 CrewDefinition/null**（理论不应）：跳过该行（防御）。
- **RUN_END（战败）后通知**：同样先通知再显示"全员阵亡 + 重新出航"。
- **start_run / 重新出航**：清空 pending，新 run 无残留通知。
- **通知已清空再次进入**（同实例不会，scene 每次新建）：pending 空 → 不重复弹。

## Dependencies

| 系统 | 接口 | 说明 |
|------|------|------|
| RunManager | `get_pending_downed_notice/clear_downed_notice/current_island_index` | 数据 + 清除 |
| UnitDataManager | `get_unit(id)->UnitDefinition` | 取阵亡者 class/name（roster 已移除，查静态数据） |
| crew-permadeath | `_on_crew_member_downed` | 填充 pending |

不改：永久死亡移除逻辑、招募/部署/run-end 既有行为（仅前置通知门控）。

## Tuning Knobs

无（白盒通知，无可调值；自动关闭/音效等留美术 story）。

## Acceptance Criteria

**AC-1：阵亡填充 pending**【单元】`_on_crew_member_downed(id)` 后 `get_pending_downed_notice()` 含 id；`clear_downed_notice()` 后为空；`start_run()` 也清空。

**AC-2：去重**【单元】同 id 两次 → pending 仅 1 条。

**AC-3：有阵亡时 RECRUITING 先显示通知卡、暂不显示招募**【集成】RECRUITING + pending 非空 → 实例化 RouteScene → 有「继续」按钮、无招募候选按钮。

**AC-4：点继续后清空并进入招募**【集成】续上 → 点 `_notice_continue_button` → pending 清空、显示招募候选。

**AC-5：无阵亡时不弹通知，直接招募**【集成】RECRUITING + pending 空 → 直接招募候选、无「继续」通知按钮（保 run_loop AC-2 回归）。

**AC-6：全量回归绿**。

## 范围/偏离

- 白盒，无灰阶图标/衬线铭文/半透明黑幕/音效（GDD Visual 留正式美术 story）。
- 通知合并为单卡多行（GDD 单张卡逐个；MVP 合并更省交互，符合"≤30 秒不拖节奏"）。
- 战中即时通知（OQ-1）不做，遵循 GDD 既定"战后汇总"。
