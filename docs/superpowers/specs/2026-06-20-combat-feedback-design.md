# 设计规格：战斗反馈/演出（白盒打击感）

> Status: Approved（brainstorming 2026-06-20）
> 目标：可玩战斗循环已通，但"没有打击感"。本增量加命中反馈、伤害浮字、KO 特效、震屏、胜负结算，
> 让每次攻击/击倒/胜负有即时视觉回报。白盒（图元 + Control + Tween，零美术/音效）。
> 引擎：Godot 4.6.3 / GDScript。几乎全视觉层（F5 验证，ADVISORY gate）。

## Overview

战斗解算/回合逻辑已完整且 242 测试绿。本增量**不碰战斗逻辑**，只订阅既有 EventBus 信号
（`damage_dealt`/`heal_executed`/`unit_downed`/`battle_won`/`battle_lost`）把结果翻译成视觉演出。
5 个职责单一的视觉部件 + BattleScene 接线。

## 配色与时长权威（battle-hud GDD / ADR-0009）
- 敌方受伤浮字 红 `#FF2222`；友方受伤 橙 `#FF8800`；治疗 绿 `#22FF66`。
- `HUD_FLOAT_DURATION` ≈ 0.6s（浮字飘动时长）。
- 震屏走 ADR-0009（3D 相机 local 偏移 + 衰减回弹）。

## 组件

### 1. DamageFloater（CanvasLayer 下 Control）— 伤害/治疗浮字 + KO
- `setup(unit_renderer: UnitRenderer) -> void`：注入渲染器以取单位世界坐标（统一位置源；
  `unit_downed` 时 turn_manager.grid_position 已置哨兵，而 UnitView.global_position 仍有效）。
- 订阅：
  - `damage_dealt(target_id, final_damage, new_hp)` → 飘字 `-{final_damage}`，颜色按目标阵营
    （crew=橙 / enemy=红）。
  - `heal_executed(target_id, amount)` → 飘字 `+{amount}` 绿。
  - `unit_downed(unit_id)` → **KO 特效**（大号、punch-in 缩放 + 上浮 + 渐隐，~0.7s，红底白字描边）。
- 位置：`Camera3D.unproject_position(view.global_position + Vector3(0, 1.6, 0))`，转屏幕坐标放 Label。
  相机取 `get_viewport().get_camera_3d()`。view 取 `unit_renderer.get_view(id)`（为空则跳过）。
- 动画：Tween 向上飘 ~40px + modulate alpha→0，结束 `queue_free()`。KO 额外做 scale 1.4→1.0 punch。
- 阵营判定：DamageFloater 注入 `faction_lookup: Callable`（`func(id) -> String`，由 BattleScene 用
  turn_manager 提供）以区分友伤橙/敌伤红（信息透明，battle-hud 要求）。

### 2. UnitView.flash_hit() — 命中闪光
- 受击单位 `_mesh` 材质 albedo 瞬白（`Color.WHITE`）再 Tween 回原 albedo（~0.15s）。
- UnitView 缓存原 albedo（_build_whitebox 时存 `_base_albedo`）。
- 由 UnitRenderer 订阅 `damage_dealt` → `get_view(target).flash_hit()` 触发。

### 3. UnitView.set_downed() 升级 — KO 退场
- 现为瞬间 `visible=false`。改为：快速下沉（position.y -= 0.5）+ 缩小（scale→0.1）+ 渐隐（modulate a→0）
  Tween ~0.3s，结束 `visible=false`。KO 大字（部件1）同时弹出，本体退场作背景。
- HP Label3D 一并随之隐藏（属 UnitView 子节点，modulate 渐隐覆盖或单独隐藏）。

### 4. CameraShake（挂相机的 Node，ADR-0009）— 震屏
- `Node`，`setup(camera: Camera3D)`：记录相机基准 local position。
- 订阅 `damage_dealt` → `shake(HIT_INTENSITY)`（小幅，~0.2s）。
- `_process(delta)`：若剩余时长>0，相机 position = 基准 + 衰减随机偏移（强度按剩余时间线性衰减），
  时长归零时复位到基准（精确回弹，ADR-0009 ②③要求）。
- 常量：`HIT_INTENSITY`（世界单位偏移幅度，小，如 0.15）、`SHAKE_DURATION` 0.2s。

### 5. BattleResultOverlay（高层 CanvasLayer 的 Control）— 胜负结算
- 订阅 `battle_won` → 显示"胜利!"；`battle_lost` → "失败…"。居中大字 + 半透背景 + `[重新开始]` 按钮。
- `[重新开始]` → `get_tree().reload_current_scene()`（重载 BattleScene 再打一场）。
- 自身 CanvasLayer layer 高（如 20，盖 HUD=5/Burst=10）。

### BattleScene 接线
- 实例化 DamageFloater / CameraShake / BattleResultOverlay（场景树节点）。
- `_damage_floater.setup(_unit_renderer, func(id): return _faction_of(id))`；`_camera_shake.setup(相机)`。
  相机由 GridBoard3D 在 _ready 代码创建 → BattleScene 经 `get_viewport().get_camera_3d()` 取（统一与
  PlayerTurnController 拾取一致）。
- UnitRenderer 扩展：`damage_dealt` 已订阅（更 HP）→ 同 handler 加 `flash_hit`。
- **TEMP：BattleScene._ready 断开 `EventBus.battle_won.disconnect(RunManager._on_battle_won)`**
  （防 RunManager→SceneManager.goto_route 因 route_scene 未赋值 assert 崩；标注待航线层接管）。

## 数据流（一次攻击）
`execute_attack` → `damage_dealt(target, n, hp)` →
  ① DamageFloater 飘 `-n`（红/橙）② UnitRenderer→view.flash_hit() 闪白 + set_hp ③ CameraShake 抖
→ 若致死 `unit_downed(target)` → ④ DamageFloater 弹 KO ⑤ view.set_downed() 下沉渐隐退场
→ 若全灭 `battle_won/lost` → ⑥ BattleResultOverlay 显示结算 + 重新开始。

## 测试策略
- **几乎全视觉 → ADVISORY F5**：飘字位置/颜色、闪光、KO、震屏回弹、结算页。
- **可测逻辑极少**：DamageFloater 伤害飘字按阵营选色（红 vs 橙）可单测一条（注入 faction_lookup，
  断言选色函数返回）。其余不强测（coding-standards：视觉 ADVISORY）。

## 范围边界（YAGNI 不做）
- 爆发华丽演出（burst presentation 仍 stub，另立）、音效、粒子/美术资源、
  伤害数字字体美化、航线层胜负流转、连击/暴击等高级反馈。

## 验收标准（F5）
- AC-1：普攻命中 → 目标头顶冒 `-N`（敌红/友橙）、目标闪白、轻微震屏。
- AC-2：治疗 → 目标冒绿 `+N`。
- AC-3：单位被打死 → 弹"KO"大字 + 本体下沉渐隐退场（不再瞬间消失）。
- AC-4：敌方全灭 → "胜利!" 结算页 + [重新开始] 可重载再战；我方全灭 → "失败…"。
- AC-5：胜利不再因航线跳转崩溃（RunManager 跳转已临时断开）。
