# 套装效果第二批：反应型三套（②b-2b）设计

> Story: set-bonus-effects-reactions（装备 epic ②b 套装效果，第二批 ②b-2b）
> 日期：2026-06-27
> 引擎：Godot 4.6.3 / GDScript / GdUnit4
> 前置：②b-2a 套装效果引擎 + 四基础套（SetEffectSystem/SetBonus，HEAD=3dd3a13，已 push origin/main）

> **⚠️ 无人模式自主起草说明**：本稿在用户离场、授权「自主选推荐项执行」期间起草。所有**效果数值与机制选择由我（助手）按既有模式取保守值自主拟定**，集中列在 §10「自主决策清单」，**待用户回来复审/调整后再进入实现**。本稿只固化设计，不附带任何已合并的战斗代码。

---

## 1. 概述（Overview）

②b-2a 让套装能在每回合开始施加增益（铁壁/狂战/医者/航海）。本批落地**三套反应型套装**——嗜血（吸血）、荆棘（反伤）、处决（斩杀）——它们不在回合开始施加，而是**响应攻击事件**（`attack_executed`）触发。新增一个与 SetEffectSystem 并列的 `SetReactionSystem`（Node，订阅 `attack_executed`），保持「回合增益」与「攻击反应」两类职责分离。所有反应造成的伤害/治疗**不再发 `attack_executed`**（沿用 ②b-2a `execute_burst_slash` 先例），杜绝二次充能、无限反伤、递归触发。阵营无关（对任何持装备+档位激活的单位生效）。

## 2. 玩家体验（Player Fantasy）

集齐嗜血的船员越打越耐久——每次挥砍都吸血回身；穿满荆棘的肉盾让近身的敌人自伤流血；处决套的杀手专盯残血，补刀不留活口。三套都在「出手的那一刻」回馈，和回合开始的持续增益（②b-2a）形成动静互补。

## 3. 详细规则（Detailed Rules）

### 3.1 触发模型
- `SetReactionSystem.setup(grid_board, turn_manager, battle_resolution)`（DI，照 AdjacencyBond/SetEffectSystem 模式），订阅 `EventBus.attack_executed(attacker_id, target_id, damage)`（`is_connected` 守卫）。
- `attack_executed` 由普通攻击（`execute_attack`）与斩（`execute_slash` 每命中）发出，带攻击者、目标、最终伤害。
- 反应处理 `on_attack_executed(attacker_id, target_id, damage)`：
  - 看**攻击者**的套装 → 嗜血、处决。
  - 看**目标**的套装 → 荆棘。
- 档位累加语义同 ②b-2a（count≥阈值激活；升级轴取最高值）。

### 3.2 防递归（关键约束）
- 嗜血治疗：走 `BattleResolution.execute_burst_heal`（emit `heal_executed`，不 emit `attack_executed`，既有）。
- 荆棘反伤 / 处决斩杀：**新增 `BattleResolution.apply_reaction_damage(target_id, amount)`**——直接扣 hp、emit `damage_dealt`、必要时 `resolve_unit_downed`，**绝不 emit `attack_executed`**（防再次触发反应/羁绊充能）。
- 因此：荆棘反伤不会触发攻击者的荆棘（攻击者非"被普攻"）、不会触发嗜血（无 attack_executed）；处决追击不会再触发处决（无 attack_executed）。链终止于一层。

### 3.3 三套效果阶梯

**嗜血 set_bloodthirst（看攻击者；命中后回血）**
- 3 件：攻击者回复 `floor(damage/4)` HP（至少 0；钳 max_hp）。
- 6 件：升级为 `floor(damage/2)`（取代 3 档比例）。
- 9 件：在 6 档基础上**新增**——相邻（八向）同阵营友军各回 `floor(damage/4)`。
- 升级轴=自身吸血比例（3→6 取最高）；新增轴=9 档的相邻外溢。

**荆棘 set_thorns（看目标；被普攻/斩命中后反弹）**
- 3 件：对攻击者造成 `1` 点反伤（`apply_reaction_damage`）。
- 6 件：升级为 `2` 点。
- 9 件：升级为 `3` 点。
- 纯升级轴（取最高固定值）。反伤可击杀攻击者（走 resolve_unit_downed）。攻击者已 Downed（同一击连锁）则跳过。

**处决 set_executioner（看攻击者；命中后斩杀残血）**
- 命中后若**目标仍存活**且 `target.current_hp <= 阈值` → 对目标追加斩杀伤害（`apply_reaction_damage`，可击杀）。
- 3 件：阈值 `3`，追加 `3`。
- 6 件：阈值 `5`，追加 `5`。
- 9 件：阈值 `7`，追加 `7`。
- 纯升级轴（阈值与追加同档取最高）。目标已被本次普攻打死则无需斩杀（is_alive 守卫）。

### 3.4 纸娃娃效果标记
- 扩展 ②b-2a 的 `SetEffectCatalog.describe(set_id, tier)`：补 set_bloodthirst / set_thorns / set_executioner 各 {3,6,9} 的中文描述（如 嗜血「吸血¼/吸血½/外溢吸血」、荆棘「反伤1/2/3」、处决「斩杀残血(≤3)/(≤5)/(≤7)」）。
- 纸娃娃逻辑（②b-2a）已对所有 set_id 通用，补描述后自动显示。

### 3.5 战斗装配
- `BattleScene._ready` 加 `set_reaction_system.setup(grid_board, turn_manager, battle_resolution)`；`BattleScene.tscn` 加 `SetReactionSystem` 节点（与 SetEffectSystem 并列）。

## 4. 公式（Formulas）

- 嗜血回血：`heal = floor(damage / 4)`（3 档）/`floor(damage / 2)`（6/9 档）；9 档相邻另回 `floor(damage / 4)`。
- 荆棘反伤：按激活档 3/6/9 → 反伤 1/2/3（取最高激活档对应值）。
- 处决：`active tier T` → 阈值/追加查表（3/6/9 → 3/5/7）；触发条件 `t.is_alive and t.current_hp <= 阈值`。
- 反应伤害：`apply_reaction_damage(tid, amount)`：`new_hp = max(0, hp - amount)`；emit `damage_dealt`；`if new_hp==0: resolve_unit_downed(tid)`；**不** emit `attack_executed`。

## 5. 边界情况（Edge Cases）

- 无装备/无激活档/敌方无装备：不反应（既有，天然）。
- 防递归：反应伤害不发 attack_executed（§3.2）——链止于一层。
- 荆棘反伤击杀攻击者：`apply_reaction_damage` → resolve_unit_downed(attacker)；execute_attack 后续 `mark_has_acted(attacker)` 对已 Downed 单位安全（仅置 flag，resolve 幂等）。
- 处决：目标已被本次普攻打死 → is_alive 守卫跳过（不重复 down）。
- 嗜血满血：heal 钳 max_hp，多余丢弃（9 档相邻同理）。
- 斩(`execute_slash`) 多目标：`attack_executed` 每命中发一次 → 反应逐目标独立处理（嗜血按每次伤害累计回血；荆棘各目标若持套各自反弹）。
- 同时持多套（如嗜血+处决，皆看攻击者）：各自独立处理（嗜血回血 + 处决补刀），互不冲突。
- damage==0 的命中（被 GUARDED/SET_GUARD 减半到 0）：嗜血 floor(0/x)=0、处决仍按目标血量判（可能触发斩杀）、荆棘仍反弹固定值（反伤与本次伤害无关）。

## 6. 依赖（Dependencies）

- `SetBonus`（②b-2a：count_sets/is_tier_active）。
- `BattleResolution`（execute_burst_heal 既有；**新增 apply_reaction_damage**）、`resolve_unit_downed`（既有）。
- `EventBus.attack_executed`（既有，普攻/斩发出）、`damage_dealt`/`heal_executed`/`unit_downed`（既有）。
- `TurnManager`（get_unit/get_alive_*）、`GridBoard`（get_adjacents/chebyshev）。
- `SetEffectCatalog`（②b-2a，扩描述）、`BattleScene`（装配）。
- **不依赖** RunManager；**不改** SetEffectSystem（职责分离）、_compute_attack_damage（不侵入伤害管线）。

## 7. 可调旋钮（Tuning Knobs）

- 嗜血比例（¼/½）、9 档相邻外溢比例。
- 荆棘反伤值 [1,2,3]。
- 处决阈值与追加 [3,5,7]。
- 各值集中为 SetReactionSystem 具名常量。

## 8. 验收标准（Acceptance Criteria）

- **AC-1（嗜血）**：攻击者持嗜血 3 件，execute_attack 命中造成 N 伤后攻击者 HP +floor(N/4)（钳 max）；6 件 +floor(N/2)；9 件相邻友军另 +floor(N/4)。
- **AC-2（荆棘）**：目标持荆棘 3/6/9 件，被普攻命中后攻击者各受 1/2/3 反伤；反伤致死走 unit_downed；反伤不再触发攻击者侧任何反应（无 attack_executed）。
- **AC-3（处决）**：攻击者持处决，命中后目标存活且 hp≤阈值(3/5/7) → 追加 3/5/7 斩杀（可致死）；目标已被普攻打死则不追加；hp>阈值不触发。
- **AC-4（防递归）**：apply_reaction_damage 不 emit attack_executed（断言反应不引发二次反应/羁绊充能）。
- **AC-5（阵营无关）**：敌方 faction 持反应套的单位同样触发（构造敌方带装备 instance 验证）。
- **AC-6（纸娃娃）**：三套各激活档在纸娃娃显示对应中文描述。
- **AC-7（装配+回归）**：BattleScene 装配 SetReactionSystem；全量 0 错误/失败/孤儿；SetEffectSystem 行为不变。

## 9. 非目标（本期不做）

- 寒霜（②b-3，需新 debuff status + 敌方回合消耗）。
- 难度系统 + 敌方按难度配装备（另立子项目）。
- 侵入式伤害管线改动（处决用 attack_executed 反应实现，不改 _compute_attack_damage）。
- 反应的美术/音效/HUD 图标表现。
- 嗜血「溢出治疗」的复杂分配（9 档仅简单相邻外溢，不做按溢出量精确分配）。

## 10. 自主决策清单（待用户复审）

无人模式下我自主拟定的、用户可能想调的点：
1. **本批含全部三套**（嗜血/荆棘/处决），而非拆分——因三套都能做成干净的 attack_executed 反应型，架构一致、低风险。
2. **处决用「命中后斩杀残血」而非「击杀不消耗行动」**——后者需 unit_downed 携带击杀者（现无）+ 回退行动点，复杂且侵入；前者是干净反应型。
3. **数值**（2026-06-27 用户逐套复审定稿）：嗜血 ¼/½ + 9档相邻¼（默认）；荆棘 **1/2/3**（用户下调，原拟 2/4/6）；处决 阈值&追加 3/5/7（默认）。均保守整数，待 playtest 校。
4. **新增 `SetReactionSystem`** 而非扩 SetEffectSystem 订阅 attack_executed——保持「回合增益 vs 攻击反应」职责分离。
5. **新增 `BattleResolution.apply_reaction_damage`**（不发 attack_executed）作为反应伤害唯一入口，防递归。
6. 反应**每命中触发**（斩多目标逐个），嗜血按每次伤害累计回血。
