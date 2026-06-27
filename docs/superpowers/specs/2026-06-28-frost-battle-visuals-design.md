# 寒霜战场视觉反馈批次 — 设计文档

> 状态：已审核（用户认可 2026-06-28）
> 范围：②b-3 寒霜套装的战场内视觉反馈（实战观感 ADVISORY 收尾）
> 前置：寒霜套装逻辑层已完结（②b-3，HEAD=8f5a01b）。纸娃娃 ✦ 描述已实现（route_scene），不在本批。

## 1. Overview（概述）

寒霜套装当前为**纯逻辑**：命中给敌方施加滞步/冰封/冻结状态，敌回合开始时结算（减半移动/移动归零/跳过整回合），结算后置一回合免疫防永冻。但战场上玩家**完全看不出**哪个敌人被冻、被冻的敌人为何不动——零视觉反馈。本批补齐三项战场内视觉表现：①被控单位的持续状态标记；②施加时的飘字；③冻结跳过的明确提示。

## 2. Player Fantasy（玩家体验）

玩家用寒霜套装命中敌人后，立刻看到敌人「结冰」：单位泛起冰蓝、头顶挂出「冻结/冰封/滞步」标签，并弹出施加飘字。轮到该敌行动时，若被冻结则弹「冻结·跳过」让玩家明白敌人是被控住而非 AI 摆烂。控制感与套装价值被直观传达。

## 3. Detailed Rules（详细规则）

### 3.1 架构决策

沿用现有「render 层全部经 EventBus 单向驱动」范式（DamageFloater / UnitRenderer 均如此）。寒霜状态存于 `BattleResolution._unit_statuses`，本批新增**两个 EventBus 信号**承载状态变化，渲染层订阅。逻辑发射可单测（BLOCKING），视觉表现走 ADVISORY 截图。

候选对比：A 新增信号（采用）；B 渲染层轮询 `get_unit_status`（耦合解算、无测试缝，否决）；C 复用回合信号自查（时序脆弱、半套，否决）。

### 3.2 新增信号（EventBus）

- `frost_applied(unit_id: int, status: StringName)` —— `SetReactionSystem._apply_frost` 在 `apply_status` 成功后发射；status ∈ {`FROST_SLOW`, `FROST_ROOT`, `FROST_FREEZE`}。
- `frost_resolved(unit_id: int, consumed: StringName)` —— `BattleResolution.resolve_frost_for_turn` 在三个**消费分支**各发一次；consumed ∈ {`FROST_FREEZE`, `FROST_ROOT`, `FROST_SLOW`}。免疫到期（无寒霜）分支**不发**。

### 3.3 组件改动

1. **UnitView**
   - 新增 `set_frost_marker(status: StringName)`：冰蓝 albedo 着色 + 头顶小标签（滞步/冰封/冻结，置于 HP 标签下方独立 Label3D）。
   - 新增 `clear_frost_marker()`：恢复 albedo、隐藏标签、清 `_frost_status`。
   - 重构 albedo 解析为 `_current_albedo()`，优先级 **frost > dimmed > base**；`flash_hit` / `set_dimmed` 统一经它取回正色，避免 albedo 通道互相覆盖。`set_selected`（emission 通道）不受影响。

2. **UnitRenderer**
   - 订阅 `frost_applied` → 对应 view `set_frost_marker(status)`。
   - 订阅 `frost_resolved` → 对应 view `clear_frost_marker()`。

3. **DamageFloater**
   - 订阅 `frost_applied` → 弹「滞步!/冰封!/冻结!」冰蓝飘字。
   - 订阅 `frost_resolved` 且 `consumed == FROST_FREEZE` → 弹「冻结·跳过」冰蓝飘字（root/slow 仅清标签，不弹飘字，避免刷屏）。

### 3.4 数据流

- 施加：我方寒霜命中敌 → `_apply_frost` 施状态 → `emit frost_applied` → 渲染层着色+标签 + 施加飘字。
- 结算：敌回合开始 → `resolve_frost_for_turn` 消费状态 → `emit frost_resolved` → 清标签；FREEZE 额外弹「冻结·跳过」。

## 4. Formulas（数值/常量）

- 冰色 `FROST_TINT ≈ Color("#7FD8FF")`；着色 = `_base_albedo.lerp(FROST_TINT, 0.5)`，飘字用纯 `FROST_TINT`。
- status→文案：`FROST_SLOW`→"滞步"，`FROST_ROOT`→"冰封"，`FROST_FREEZE`→"冻结"（渲染层定义 dict，与战斗逻辑常量解耦）。

## 5. Edge Cases（边界）

- 同帧致死后施加：`_apply_frost` 已有三重生存守卫（null/!is_alive/hp≤0 提前返回），不会对死单位发 `frost_applied`。
- 免疫态：`_apply_frost` 命中免疫单位时提前返回，不施加、不发信号。
- 无寒霜单位走结算：`resolve_frost_for_turn` 免疫到期分支不发 `frost_resolved`，渲染层无副作用。
- view 不存在（相机/视图为空）：渲染层与飘字均已有 null 守卫（`get_view`/`get_camera_3d`），缺失时静默跳过不崩。
- 单位被击倒：`set_downed` 隐藏整个 view，残留标签随之不可见，无需专门清理。

## 6. Dependencies（依赖）

- `src/autoloads/event_bus.gd`（新增 2 信号）
- `src/battle/set_reaction_system.gd`（`_apply_frost` 发 `frost_applied`）
- `src/battle/battle_resolution.gd`（`resolve_frost_for_turn` 发 `frost_resolved`）
- `src/render/unit_view.gd`（标记 API + albedo 重构）
- `src/render/unit_renderer.gd`（订阅）
- `src/render/damage_floater.gd`（订阅）

## 7. Tuning Knobs（可调项）

- `FROST_TINT` 冰色、lerp 混合比例（0.5）。
- 标签字号 / 偏移位置。
- 飘字时长（复用 `FLOAT_DURATION`）。
- 文案 dict（滞步/冰封/冻结）。

## 8. Acceptance Criteria（验收标准）

逻辑（BLOCKING 自动化单测）：

- AC-1：`_apply_frost` 对 9/6/3 档分别发 `frost_applied(target, FROST_FREEZE/ROOT/SLOW)`。
- AC-2：`_apply_frost` 命中免疫单位时不发 `frost_applied`。
- AC-3：`resolve_frost_for_turn` 对持 FREEZE/ROOT/SLOW 的单位各发一次 `frost_resolved(id, 对应 consumed)`。
- AC-4：`resolve_frost_for_turn` 对无寒霜单位（免疫到期分支）不发 `frost_resolved`。
- AC-5：全量回归绿、零孤儿、零导入错误。

视觉（ADVISORY，F5 截图 + 签收）：

- AC-6：被冻结敌人呈冰蓝着色 + 头顶「冻结」标签。
- AC-7：施加瞬间弹对应飘字（滞步!/冰封!/冻结!）。
- AC-8：冻结敌回合被跳过时弹「冻结·跳过」。

## 9. 非目标（本批不做）

- 敌方意图 HUD（`intent_declared` 目前零消费方，属独立更大功能）。
- 玩家单位寒霜视觉（spec §9，敌方无装备 moot）。
- 寒霜音效。
- 状态叠加/层数视觉（单一最高档，沿用逻辑层约束）。
