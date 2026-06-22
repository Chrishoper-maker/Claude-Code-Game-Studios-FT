# run-end 解锁提示设计

> Story: run-end-unlock-notice (#16) · 2026-06-22 · 引擎 Godot 4.6.3 / GDScript / GdUnit4

## 1. Overview

末岛通关胜利会触发 `MetaProgress.unlock_next()` 解锁下一名悬赏船员，但当前
`RunManager._on_battle_won()` 丢弃了它的返回值，run-end 总结页也不展示解锁结果，
玩家无从得知本次通关换来了什么。本故事让 RunManager 记住本航新解锁的船员 id，
并在 run-end 总结页（仅胜利结局）追加一行白盒解锁提示。纯逻辑/白盒文字，无动画/音效。

## 2. Player Fantasy

通关那一刻，总结页明确告诉玩家"你的功绩解锁了新船员 X"——把抽象的 meta 进度
变成可见的即时回报，鼓励再次出航去用上新解锁的人。

## 3. Detailed Rules

### Rule 1 — RunManager 记录本航解锁
- 新字段 `_unlocked_this_run: String = ""`（本航新解锁的船员持久 id；空串=无解锁）。
- `start_run()` 起航时清空：`_unlocked_this_run = ""`。
- `_on_battle_won()` 末岛胜利分支：把现有 `MetaProgress.unlock_next()` 调用的返回值
  赋给 `_unlocked_this_run`（`_unlocked_this_run = MetaProgress.unlock_next()`）。
  非末岛胜利分支与 `_on_battle_lost()` 不触碰该字段（保持 ""）。
- 查询方法 `get_unlocked_this_run() -> String`：返回 `_unlocked_this_run`。

### Rule 2 — RouteScene run-end 展示解锁行
- `_show_run_end()` 在幸存名单 + 本航阵亡名单之后、"重新出航"按钮之前，
  若 `RunManager.get_unlocked_this_run() != ""`：
  - 用 `UnitDataManager.get_unit(id)` 解析，且 `is CrewDefinition` 守卫；
  - 追加一行 Label：`"解锁新船员：%s · %s" % [crew.unit_class, crew.display_name]`。
  - 解析失败（非 CrewDefinition / 不存在）→ 不追加（防御，正常不发生）。
- 不新增门控卡、不改 `_notice_then` 折损通知流程。

## 4. Formulas

无数值公式。

## 5. Edge Cases

- **全部 unlockable 已解锁**：`unlock_next()` 返 "" → `_unlocked_this_run=""` → 无解锁行。
- **失败结局**：`_on_battle_lost()` 不解锁 → `_unlocked_this_run` 保持 "" → 无解锁行。
- **非末岛胜利**：中途胜利进入招募，不触碰 `_unlocked_this_run`（保持 ""）。
- **重新出航**：`start_run()` 清空，旧解锁提示不残留到下一航。
- **不持久化**：run-end 不会被存档恢复（存档在 RUN_END 时删除），`_unlocked_this_run`
  为纯展示态，无需进 to_save_dict。
- **解锁 id 解析失败**：UI 防御性跳过，不崩。

## 6. Dependencies

- `MetaProgress.unlock_next()`（既有，返回新解锁 id 或 ""）。
- `RunManager._on_battle_won` / `start_run`（既有）。
- `UnitDataManager.get_unit`（既有，解析 CrewDefinition）。
- `RouteScene._show_run_end`（既有 run-end 总结渲染）。

## 7. Tuning Knobs

- 解锁提示文案（"解锁新船员：职业 · 名"）。
- 展示位置（当前：幸存/阵亡名单之后、重新出航按钮之前）。

## 8. Acceptance Criteria

- **AC-1**：末岛胜利后 `get_unlocked_this_run()` 返回 `MetaProgress.unlock_next()` 解锁的 id
  （未全解锁时为非空）。
- **AC-2**：全部 unlockable 已解锁时末岛胜利后 `get_unlocked_this_run()` 返回 ""。
- **AC-3**：`start_run()` 后 `get_unlocked_this_run()` 返回 ""。
- **AC-4**：失败结局（`_on_battle_lost`）后 `get_unlocked_this_run()` 返回 ""。
- **AC-5**：RouteScene run-end 页在 `get_unlocked_this_run()` 非空时含一行包含该船员 display_name
  的解锁提示文字；为空时无该行。
- **AC-6**：全量回归绿、`--headless --import` 零错、零孤儿。

## 9. 非目标（YAGNI）

- 独立门控解锁卡（如折损通知那样的单独界面 + 继续按钮）。
- 解锁动画 / 音效 / 立绘（需美术资源）。
- 解锁提示持久化 / 跨会话回看历史解锁。
- 一次通关解锁多名船员（当前 unlock_next 每次只解一名）。
