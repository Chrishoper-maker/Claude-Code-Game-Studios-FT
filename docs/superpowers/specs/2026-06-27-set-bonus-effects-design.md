# 套装效果引擎 + 四基础套（②b-2a）设计

> Story: set-bonus-effects（装备 epic ②b 套装效果，第二期首批 ②b-2a）
> 日期：2026-06-27
> 引擎：Godot 4.6.3 / GDScript / GdUnit4
> 前置：②b-1 套装地基（8 套 72 件 + 累积获取 + 套装计数器，HEAD=826a7b1，已 push origin/main）

> **②b 三期/分批回顾**：②b-1 地基（已完成）→ **②b-2 效果引擎**（本稿 ②b-2a = 框架+四基础套；②b-2b = 嗜血/荆棘/处决三反应套）→ ②b-3 寒霜（新 debuff 机制）。
> **另立子项目**：难度系统 + 敌方按难度配装备（依赖本效果引擎，单独 brainstorm→spec→plan）。

---

## 1. 概述（Overview）

②b-1 让套装能集齐、能看进度，但不产生任何战斗加成。本期搭建**套装效果引擎**并落地**四基础套**（铁壁/狂战/医者/航海）的 3/6/9 效果。引擎**阵营无关**——对任何「持有装备且套装档位激活」的存活单位生效（当前 crew 生效；敌方无装备故暂无效果，将来敌方配装后零改动自动套用）。效果在每回合开始（`round_started`）施加，复用现有 status / heal / 相邻扫描机制，仅对 BattleResolution 做小幅扩展（新增 3 个 round-status）。纸娃娃追加套装效果中文描述标记。

## 2. 玩家体验（Player Fantasy）

集齐套装终于"有用"了：穿满铁壁的船员每回合自动减伤、滚到半甲还能持续回血；狂战船员越打越狠；医者撑起全队续航；航海给周围弟兄加 buff。摊开人形面板不仅看到「铁壁 9/9」，还看到这套此刻到底给了什么——成长与构筑的回报第一次在战斗里兑现。

## 3. 详细规则（Detailed Rules）

### 3.1 档位语义（累加）
- 某套「档位 T 激活」⟺ 该单位该套持有件数 `count >= T`，T ∈ {3,6,9}。
- **累加**：集 9 件时 3/6/9 三档效果同时生效。每套的应用逻辑由激活档位组合出最终效果，分两类档位：
  - **升级/取代型**（沿同一轴）：高档替换低档同类，只保留最高变体。如铁壁 `GUARDED→SET_GUARD`、狂战 `AURA→FRENZY→FRENZY_PERSIST`、医者自愈量 `3→6`、航海半径 `1→2`。
  - **新增型**（不同轴）：各档新增的独立效果叠加保留。如铁壁 6 档的自愈、航海 6 档的 GUARDED、医者 6 档的"相邻目标"。
- 套装件数由单位的 `UnitInstance.equipment`（{slot:int → EquipmentDefinition}）现算，每件读 `set_id`。**不经 RunManager**（战斗层自足、阵营无关、可测）。

### 3.2 施加时机
- 订阅 `EventBus.round_started`：每轮起遍历 `TurnManager` 全体**存活**单位，对每个单位的每个**有激活档位的套**施加该套效果。
- 装备战斗中不变 → 档位每单位每场恒定；效果是「每回合开始施加的增益」，随既有 status 生命周期消耗/清除。
- 敌方/无装备/无激活档位单位：跳过（无副作用）。

### 3.3 四套效果阶梯

**铁壁（防御/生存）**
- 3 件：每回合开始获得 `GUARDED`（本回合首次受击伤害减半）。复用现有 `STATUS_GUARDED`。
- 6 件：每回合开始 +3 HP 自愈（钳 `max_hp`）。复用 `execute_burst_heal`。
- 9 件：改获「钢铁壁垒」`STATUS_SET_GUARD`（本轮**所有**受击均减半，命中不消耗）。

**狂战（输出）**
- 3 件：每回合开始获得 `AURA`（下次攻击 +1 伤害）。复用现有 `STATUS_AURA`。
- 6 件：升级为「狂热」`STATUS_FRENZY`（下次攻击 +2，取代 AURA）。
- 9 件：升级为「持续狂热」`STATUS_FRENZY_PERSIST`（本轮**每次**攻击都 +2，不消耗）。

**医者（续航）**
- 3 件：每回合开始自身 +3 HP（钳 max_hp）。
- 6 件：每回合开始相邻（八向）友军也各 +3 HP。
- 9 件：治疗量翻倍——自身 & 相邻各 +6 HP（取代 3/6 档的 +3）。

**航海（战术/团队增益）**
- 3 件：每回合开始给相邻（八向）友军施加 `AURA`（下次攻击 +1）。
- 6 件：每回合开始也给相邻友军施加 `GUARDED`（首次受击减半）。
- 9 件：上述团队增益半径由相邻（切比雪夫 1）扩大到切比雪夫 ≤2。

「友军/同阵营」按**施加单位自身 faction** 判定（crew 给 crew，将来 enemy 给 enemy）。

### 3.4 BattleResolution 扩展（效果引擎所需）
- 新增 3 个 round-status 常量：`STATUS_FRENZY`（&"FRENZY"）、`STATUS_FRENZY_PERSIST`（&"FRENZY_PERSIST"）、`STATUS_SET_GUARD`（&"SET_GUARD"）。
- `_compute_attack_damage` 增益项改为：`frenzy(+2) > aura(+1)` 取高（`STATUS_FRENZY` 或 `STATUS_FRENZY_PERSIST` 任一存在则 +2，否则 `STATUS_AURA` 则 +1，否则 0）；攻击后消耗 `STATUS_FRENZY` 与 `STATUS_AURA`，但**不消耗** `STATUS_FRENZY_PERSIST`（slash 同步同逻辑）。
- `_apply_guard` 增读 `STATUS_SET_GUARD`：存在则减半但**不消耗**（优先于 `STATUS_GUARDED`；set_guard 在则不消耗 GUARDED）。
- `clear_round_statuses`（round_end 调）一并清除 `STATUS_FRENZY` / `STATUS_FRENZY_PERSIST` / `STATUS_SET_GUARD`（与 GUARDED 同生命周期；`STATUS_AURA` 仍按原状跨轮保留）。
- **炮击不受影响**：`execute_cannon` 仍仅 base 伤害（不读 aura/frenzy，沿用现状）；攻击增益仅作用于普通攻击与斩（slash）。

### 3.5 纸娃娃效果标记
- RouteScene `_build_paperdoll` 的套装行（②b-1 已显示「set_id count/9（已激活 N）」）后，追加该套**当前激活各档**的中文效果描述（如「铁壁 9/9 ✦钢铁壁垒·本轮全减半 / +3自愈 / 首击减半」）。
- 描述取自**单源效果描述表** `SetEffectCatalog.describe(set_id, tier) -> String`（仅四基础套有描述；其余套返回空，留后续期填充）。白盒文字、无美术。

## 4. 公式（Formulas）

- 档位激活：`active(unit, set_id, T) = (set_count(unit, set_id) >= T)`，T∈{3,6,9}。
- 攻击增益项：`bonus = 2 if (FRENZY or FRENZY_PERSIST) else (1 if AURA else 0)`；最终伤害仍 `base + min(modifier, MAX_MODIFIER_SUM) + bonus`（bonus 取代原 aura 项，独立不入 cap，沿用现有管线）。
- 减伤：`STATUS_SET_GUARD` 或 `STATUS_GUARDED` 存在 → `dmg / GUARD_DIVISOR`（floor）；set_guard 不消耗、guarded 消耗。
- 自愈：`new_hp = min(current_hp + amount, max_hp)`（复用 execute_burst_heal）。
- 团队半径：3/6 档 = `chebyshev <= 1`（相邻八向）；9 档 = `chebyshev <= 2`。

## 5. 边界情况（Edge Cases）

- 无装备 / 无激活档位 / 敌方：跳过，无效果。
- 多套混搭同时激活：各套独立施加（如铁壁3+狂战3 → GUARDED 与 AURA 各得）。
- 9 档「钢铁壁垒」与 3 档 GUARDED 同时激活：`_apply_guard` 先查 SET_GUARD，主导（不重复减伤）。
- 自愈钳 max_hp；满血 +0。
- Downed 单位（is_alive==false）：不施加。
- 持续狂热（FRENZY_PERSIST）本轮多次攻击均 +2；round_end 清除（下一轮 round_started 重新施加）。
- `STATUS_AURA` 仍跨轮保留（沿用既有语义，不改），但每轮 round_started 会被狂战 6/9 档以 FRENZY 取代（取高），无冲突。
- 航海团队增益施加给**施加者的相邻友军**；空范围（无相邻友军）→ 无操作。

## 6. 依赖（Dependencies）

- `UnitInstance.equipment`（②b-1，{slot:def}，每件含 set_id）。
- `EquipmentDefinition.set_id`（②b-1）。
- `BattleResolution`（apply_status / get_unit_status / _consume_status / _compute_attack_damage / _apply_guard / clear_round_statuses / execute_burst_heal）——本期扩展。
- `TurnManager`（get_unit / 存活单位遍历）、`GridBoard`（get_adjacents / chebyshev / 占用）、`EventBus.round_started`。
- `BattleScene`（_ready 装配 SetEffectSystem）、`BattleScene.tscn`（加节点）。
- `RouteScene._build_paperdoll`（②b-1）+ 新 `SetEffectCatalog`。
- **不依赖** RunManager（战斗层自足）。

## 7. 可调旋钮（Tuning Knobs）

- 各套各档数值：铁壁自愈 +3、狂热 +2、医者自愈 +3/翻倍 +6、AURA +1。
- 减伤除数 `GUARD_DIVISOR`（既有 =2）。
- 团队增益半径（3/6 档 =1，9 档 =2）。
- 套装阈值 `[3,6,9]`（②b-1 既有 SET_TIERS）。

## 8. 验收标准（Acceptance Criteria）

- **AC-1（SetBonus）**：从 UnitInstance/equipment 正确算 `{set_id:count}`；`is_tier_active` 累加边界（count 2→否、3→是、6→是、9→是）正确；混搭多套；空装备返回空/否。
- **AC-2（铁壁）**：3 件单位 round_started 后持 GUARDED；6 件 round_started 后 HP+3（钳 max）；9 件持 SET_GUARD 且本轮多次受击均减半。
- **AC-3（狂战）**：3 件 round_started 后持 AURA（攻击 +1）；6 件持 FRENZY（攻击 +2 且取代 AURA）；9 件持 FRENZY_PERSIST（同轮两次攻击均 +2）。
- **AC-4（医者）**：3 件自身 +3；6 件相邻友军 +3；9 件 +6（自身&相邻）；钳 max_hp。
- **AC-5（航海）**：3 件相邻友军得 AURA；6 件相邻友军得 GUARDED；9 件半径扩到 ≤2 格（断言 2 格外不得、2 格内得）。
- **AC-6（阵营无关）**：给一个 enemy faction 的带装备 instance，round_started 后同样得到对应效果（证明引擎不限 crew）。
- **AC-7（BattleResolution 扩展）**：`_compute_attack_damage` frenzy 取高/persist 不消耗、`_apply_guard` set_guard 减半不消耗、`clear_round_statuses` 清除三新 status——各有针对性单测。
- **AC-8（纸娃娃标记）**：激活档位的套在纸娃娃显示对应中文效果描述；未激活/无描述套不显。
- **AC-9（装配 + 回归）**：BattleScene 装配 SetEffectSystem；全量测试 0 错误/失败/孤儿。

## 9. 非目标（本期不做）

- 嗜血/荆棘/处决（②b-2b，需 attack_executed/unit_downed 反应钩子 + 击杀者追踪）。
- 寒霜（②b-3，新 debuff status + 敌方回合消耗）。
- 难度系统 + 敌方按难度配装备（另立子项目）。
- 战斗 HUD 内的实时效果图标/动画（本期只做纸娃娃文字标记）。
- 套装效果的美术/音效表现。
