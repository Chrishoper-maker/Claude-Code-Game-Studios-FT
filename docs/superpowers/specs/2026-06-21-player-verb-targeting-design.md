# 玩家动词选靶（aura / heal / displace）设计

> **Status**: Approved（自主推进，用户授权"用推荐项自行决策"2026-06-21）
> **Author**: Chris（授权）+ Claude Code
> **Date**: 2026-06-21
> **Epic**: battle / player-input（player-turn-input-hud 续作）

## Overview

`PlayerTurnController.do_verb()` 当前只支持 slash（剑豪）/guard（铁壁）两种无目标动词；aura（乐手）/heal（医师）/displace（航海士）/cannon（炮手）落到 `_:` 分支仅 `push_warning` 不执行——这三类职业的船员**无法使用职业动词**。本增量补齐玩家侧动词选靶：
- **aura**：无目标，立即执行（execute_aura）。
- **heal**：选**相邻**存活友方 → execute_verb(HEAL)。
- **displace**：选**相邻**存活敌方 → execute_verb(MOVE)（推离方向由引擎 `_cardinal_toward` 内部推导）。
- **cannon**：选处于基本方向直线（同行/同列）、曼哈顿 ∈ [GUNNER_MIN_RANGE(2), attack_range] 的敌方 → execute_verb(CANNON)，沿该向穿透（方向引擎内推导）。**已含**（初稿曾拟延后，后确认可纳入同一选靶模式：选直线上的敌方即等价于选方向，且尊重最小/最大射程）。

复用现有 mode 化选靶框架（MOVE/ATTACK 同款：进入模式→算合法格→高亮→点击格→派发），逻辑可无头单测；鼠标拾取/高亮为视觉壳（既有）。

## Player Fantasy

医师、乐手、航海士不再是"只能走和打"的半残单位——玩家能主动治疗、增益、把敌人推开，构筑层的职业差异在战斗中真正落地。

## Detailed Rules

### Rule 1：do_verb 分流

`do_verb()`（HUD[技能]按钮）按选中单位 `class_action_id`：
- `slash` → `execute_slash(self)`（不变）
- `guard` → `execute_guard(self, self)`（不变）
- `aura` → `execute_aura(self)`（新增，无目标，立即）
- `heal` / `displace` → `_begin_verb_targeting()`（进入 VERB 选靶模式）
- 其它（cannon 等）→ `push_warning`（保留，未支持）
无目标动词执行后 `_set_mode(IDLE)`。前置守卫不变：非我方回合 / 未选单位 / `has_used_verb` / `class_action_id==""` → 直接返回。

### Rule 2：VERB 选靶模式

新增 `Mode.VERB` 与成员 `_pending_verb: int`。`_begin_verb_targeting()`：记 `_pending_verb = _verb_type_for(cid)`（heal→`BattleResolution.VerbType.HEAL`、displace→`VerbType.MOVE`），`set_mode(Mode.VERB)`（算目标+高亮）。

`_compute_targets(Mode.VERB)`（选中单位未 `has_used_verb`）：
- `heal`：所有存活友方（**排除自身**）中 `GridBoard.chebyshev(caster, ally)==1` 者的格。
- `displace`：所有存活敌方中 `chebyshev(caster, enemy)==1` 者的格。

`handle_cell_click(cell)` 在 `Mode.VERB`：heal 取 `_ally_at(cell)`、displace 取 `_enemy_at(cell)`；命中合法目标 → `execute_verb(caster, _pending_verb, target)` → `_set_mode(IDLE)`。非合法格（不在 `_valid_targets`）由既有 `handle_cell_click` 守卫拦截。

### Rule 3：相邻为默认作用范围（设计决策）

heal/displace 的合法目标 = **chebyshev 相邻（==1）**。理由：本作空间核心是八向相邻（slash AoE、aura 增益、羁绊判定均以相邻为度），引擎未给 heal/displace 定义独立射程；相邻是与全局一致的保守默认，非平衡杜撰。cannon 是文档化的远程例外（GUNNER_MIN_RANGE），故单列。**可调点**：未来若 GDD 为 heal/displace 定义专用射程，改 `_compute_targets` 即可。

### Rule 4：可用动作查询

`get_available_actions()["verb"]`（HUD 据此启用[技能]按钮）：未 `has_used_verb` 时——
- `slash`/`guard`/`aura` → true（无目标恒可用）。
- `heal`/`displace` → `not _compute_targets(Mode.VERB).is_empty()`（有相邻合法目标才可用）。
- 其它 → false。

## Formulas

相邻判定：`GridBoard.chebyshev(a, b) == 1`（八向相邻，既有静态方法）。

## Edge Cases

- **heal 无相邻友方**：VERB 目标空 → 高亮清空；`get_available_actions["verb"]` 为 false。
- **displace 无相邻敌方**：同上空目标。
- **点非高亮格**：既有 `if not cell in _valid_targets: return` 拦截，不执行、不耗动词。
- **已用动词**：守卫返回；目标计算返回空。
- **medic 想自疗**：本增量 heal 排除自身（相邻不含自身）；自疗留后续（若需，加 range-0 自指）。
- **displace 把敌推到边界/占用**：execute_displace 内部逐格判定遇阻即停（既有逻辑），即便贴边也合法发动（标记动词）。
- **aura 无相邻友方**：execute_aura 自然 buff 空集，仍标记动词（既有行为，无目标动词总可发动）。

## Dependencies

| 系统 | 接口 | 说明 |
|------|------|------|
| BattleResolution | `execute_verb(unit, VerbType, target)` / `execute_aura(unit)` / `VerbType` 枚举 | 统一分发器，方向型内部推导；aura 直调 |
| GridBoard | `chebyshev(a,b)`（静态） | 相邻目标判定 |
| TurnManager | `get_alive_allies/enemies` / `get_unit` | 目标枚举 |

不改：BattleResolution 动词实现、攻击/移动/爆发既有流程、视觉壳（_unhandled_input/拾取/高亮）。

## Tuning Knobs

| 项 | 默认 | 说明 |
|----|------|------|
| heal/displace 作用范围 | chebyshev==1（相邻） | 见 Rule 3；改 `_compute_targets(Mode.VERB)` |

## Acceptance Criteria

**AC-1：aura 无目标立即执行并标记动词**【单元】选中乐手（相邻一友方）→ do_verb → 相邻友方获 STATUS_AURA、乐手 `has_used_verb`、mode IDLE。

**AC-2：heal 进入选靶、点相邻友方治疗**【单元】选中医师（相邻一受损友方）→ do_verb → mode==VERB 且目标含该友方格 → handle_cell_click(友方格) → 友方 current_hp 增加（钳 max）、医师 has_used_verb、mode IDLE。

**AC-3：displace 进入选靶、点相邻敌方推离**【单元】选中航海士（相邻一敌方，敌后方有空格）→ do_verb → mode==VERB 且目标含敌方格 → handle_cell_click(敌方格) → 敌方 grid_position 沿离航海士方向后移、航海士 has_used_verb。

**AC-4：heal 无相邻友方 → 无目标、verb 不可用**【单元】医师周围无友方 → do_verb 进 VERB 但 `get_valid_targets` 空；`get_available_actions["verb"]` 为 false。

**AC-5：cannon 选直线敌方（射程内）穿透命中**【单元】选中炮手（attack_range≥3，同列一近一远敌）→ do_verb → mode==VERB 且目标含远敌格、不含 < 最小射程的近敌格 → click 远敌 → 穿透命中（远敌 hp 降）、炮手 has_used_verb、mode IDLE。

**AC-6：全量回归绿**。

## 范围/偏离

- aura/heal/displace/cannon 全含（6 职业动词全部玩家可用）。
- cannon 选靶 = 直线 + [GUNNER_MIN_RANGE, attack_range]；选直线敌方等价于选穿透方向。
- heal 不含自疗（相邻排除自身）。
- 视觉（高亮色/拾取）复用既有壳，不新增美术。
