# 主菜单（Main Menu）设计

> **Status**: Approved（用户确认 2026-06-21）
> **Author**: Chris + Claude Code
> **Date**: 2026-06-21
> **System**: 主菜单 / 出航入口（boot 流程）

## Overview

当前游戏 `main_scene` 直接是 `RouteScene.tscn`，启动即在 IDLE 分支 `_begin_run` 自动开一局——**没有标题/出航入口**。本增量加一个白盒主菜单作为启动场景：标题 + 解锁进度 + [出航] + [退出]。玩家点「出航」才开始新 run。**不含**"继续上次航程"（无进行中 run 存档）、设置、美术。

## Player Fantasy

启动游戏先看到《孤帆棋海》的标题与"悬赏解锁 N/3"——玩家感到这是一段会持续的航程（meta 进度可见），按下「出航」主动启程，而非被直接丢进战斗。

## Detailed Rules

### Rule 1：MainMenu 场景作为启动场景

新增 `scenes/MainMenu.tscn`（根 Control）+ `src/ui/main_menu.gd`（`class_name MainMenu extends Control`，白盒）。`project.godot` 的 `run/main_scene` 由 `res://scenes/RouteScene.tscn` 改为 `res://scenes/MainMenu.tscn`。SceneManager **不改**（MainMenu 直接调 `SceneManager.goto_route()`；无返回菜单入口，故不新增 `goto_main_menu`）。

### Rule 2：菜单内容（白盒，只用按钮）

`_ready` 构建（VBoxContainer，先 add_child 再 set_anchors_preset(PRESET_CENTER)）：
1. 标题 Label：`《孤帆棋海》`
2. 解锁进度 Label（存 `_unlock_label`）：`"悬赏解锁 %d / %d" % [MetaProgress.unlocked_crew_ids.size(), MetaProgress.get_unlock_order().size()]`
3. 「出航」Button（存 `_set_sail_button`）：`pressed` → `_on_set_sail`
4. 「退出」Button（存 `_quit_button`）：`pressed` → `_on_quit`

### Rule 3：出航流程

`_on_set_sail()` → `_nav_set_sail.call()`（默认 `SceneManager.goto_route()`）。启动时 RunManager `_phase` 为 RUN_IDLE → RouteScene `_ready` 命中 IDLE 分支 `_begin_run`（`start_run` 填起始编制 → `_enter_deploy` → 部署 → 战斗）。RouteScene 与 run-end"重新出航"均不改。

### Rule 4：退出

`_on_quit()` → `_nav_quit.call()`（默认 `get_tree().quit()`）。

### Rule 5：DI 导航接缝（可测性）

导航与退出经可注入 Callable，避免测试真的切场景 / 退出测试运行器（沿用 RunManager `_goto_*` 接缝模式）：
- `var _nav_set_sail: Callable`、`var _nav_quit: Callable`；`func _default_set_sail() -> void: SceneManager.goto_route()`、`func _default_quit() -> void: get_tree().quit()`。
- `_ready` 起始赋默认（在构建 UI 前）；`_on_set_sail/_on_quit` 调对应 Callable。
- 测试在 `add_child`（触发 `_ready` 赋默认）后覆盖为记录闭包，再调 `_on_*`。

## Formulas

`解锁分母 M = MetaProgress.get_unlock_order().size()`（= unlockable 船员数 = 3）；`已解锁 N = MetaProgress.unlocked_crew_ids.size()`。

## Edge Cases

- **无任何解锁（首启）**：标签显示 `悬赏解锁 0 / 3`。
- **全解锁**：`悬赏解锁 3 / 3`。
- **RunManager 非 IDLE 时进入 MainMenu**（理论不发生——MainMenu 只在启动展示、无返回入口）：`_on_set_sail` 仍 `goto_route`，RouteScene 按当时 phase 分支（防御性，不崩）。MVP 不构造该路径。
- **退出在编辑器/测试**：经 `_nav_quit` 接缝，测试覆盖为 no-op，不退出运行器。

## Dependencies

| 系统 | 接口 | 说明 |
|------|------|------|
| SceneManager | `goto_route()` | 出航 → RouteScene |
| MetaProgress | `unlocked_crew_ids` / `get_unlock_order()` | 解锁进度展示 |
| RouteScene（间接） | IDLE→`_begin_run` | 出航后由其起航；本系统不改 RouteScene |

不改：SceneManager、RouteScene、RunManager、run-end 流程。仅改 `project.godot` 的 main_scene。

## Tuning Knobs

无（白盒入口，无可调数值；标题文案、解锁文案为字面量）。

## Acceptance Criteria

**AC-1：菜单渲染出航/退出按钮 + 解锁进度**【集成】实例化 MainMenu → `_set_sail_button`/`_quit_button` 非 null；`_unlock_label.text` == `"悬赏解锁 0 / 3"`（MetaProgress 清空时）。

**AC-2：解锁进度反映 MetaProgress**【集成】MetaProgress 解锁 2 名 → 实例化 MainMenu → `_unlock_label.text` == `"悬赏解锁 2 / 3"`。

**AC-3：出航触发导航接缝**【集成】覆盖 `_nav_set_sail` 为记录闭包 → `_on_set_sail()` → 闭包被调用 1 次（不真的切场景）。

**AC-4：退出触发退出接缝**【集成】覆盖 `_nav_quit` 为记录闭包 → `_on_quit()` → 闭包被调用 1 次（不退出运行器）。

**AC-5：main_scene 指向 MainMenu**【冒烟】`project.godot` `run/main_scene == "res://scenes/MainMenu.tscn"`；导入零错。

**AC-6：全量回归绿**。

## 范围/偏离

1. 仅标题 + 解锁进度 + 出航 + 退出；**无"继续上次航程"**（需通用存档；MetaProgress 不存进行中 run）。
2. 白盒，无背景美术/音乐/设置（留后续美术 story）。
3. 不新增"返回主菜单"入口（YAGNI，无触发点）→ 不动 run-end。
4. SceneManager 不加 `goto_main_menu`（无调用方；main_scene 由项目设置指定）。
