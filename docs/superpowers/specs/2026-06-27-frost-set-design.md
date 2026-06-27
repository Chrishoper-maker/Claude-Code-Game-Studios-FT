# 寒霜套装设计（②b-3）

> Story: frost-set（装备 epic ②b 套装效果，第三批 ②b-3）
> 日期：2026-06-27
> 引擎：Godot 4.6.3 / GDScript / GdUnit4
> 前置：②b-2b 反应套（嗜血/荆棘/处决，HEAD=945a72c，已 push origin/main）

---

## 1. 概述（Overview）

寒霜 `set_frost` 是 ②b-1 八套装中**最后一套未实现**的效果。它是一套**冻结型控制（CC）debuff**：持有寒霜的单位命中敌方时给目标施加寒霜状态，该状态在**敌方那名单位的下个回合结算时生效并消费**——按档位令其减速 / 不能移动 / 整回合跳过。寒霜不造成伤害，填补现有八套中唯一的硬控/控制生态位（其余套为伤害/续航/团队增益）。施加复用 ②b-2b 的 `SetReactionSystem`（`attack_executed` 反应）；结算挂在敌方回合执行入口（`EnemyAI._on_enemy_turn_started`）。为防 9 档永冻，单位被冻结结算后获得一回合寒霜免疫。

## 2. 玩家体验（Player Fantasy）

集齐寒霜的船员是战场的控场手——一击之下敌人步履迟滞、继而冻在原地、满套时整整一回合动弹不得。玩家用一次攻击换取对一个威胁目标的压制，配合队友集火或重新走位。寒霜不靠伤害取胜，而是靠"让它打不到你"。

## 3. 详细规则（Detailed Rules）

### 3.1 施加模型（反应型）
- `SetReactionSystem.on_attack_executed(attacker_id, target_id, damage)` 攻击者侧新增寒霜分支（与嗜血/处决同侧）。
- 攻击者持 `set_frost`（任一档激活）且**目标非 `FROST_IMMUNE`** → 按攻击者持有的**最高激活档**给目标 `apply_status` 对应寒霜状态。
- `attack_executed` 由普攻（`execute_attack`）与斩（`execute_slash` 每命中）发出，故普攻与斩均触发施加。
- **阵营无关**（代码层不过滤 faction）；但寒霜效果仅在 AI 敌方回合结算，故对玩家单位施加只是无害空状态（无玩家回合冻结，见 §9）。

### 3.2 三档阶梯（被施寒霜的单位"下个回合"生效）
- **3 件 `FROST_SLOW`（滞步）**：该敌下回合**有效移动范围减半** `floor(move_range / 2)`，仍可攻击。
- **6 件 `FROST_ROOT`（冰封）**：该敌下回合**不能移动**（有效移动范围 0），仍可攻击。
- **9 件 `FROST_FREEZE`（冻结）**：该敌下回合**整回合跳过**（不移动、不攻击 = 强制 WAIT）。
- 升级轴取最高激活档（同 ②b-2a/②b-2b）：施加时只挂当前最高档对应的单一寒霜状态。

### 3.3 结算 + 防永冻（`BattleResolution.resolve_frost_for_turn`）
- 新增 `resolve_frost_for_turn(unit_id: int) -> Dictionary`，返回 `{"skip": bool, "move_cap": int}`（`move_cap == -1` 表示不限制 = 正常移动范围）。由 `EnemyAI` 在每名敌方单位回合开始时调用一次。
- **若该单位持寒霜状态**（FROST_FREEZE / FROST_ROOT / FROST_SLOW，按此优先级取其一）：
  - 计算 outcome：FREEZE → `{skip: true, move_cap: 0}`；ROOT → `{skip: false, move_cap: 0}`；SLOW → `{skip: false, move_cap: floor(get_move_range()/2)}`。
  - **消费**该寒霜状态（`_consume_status`）。
  - 给该单位施 `FROST_IMMUNE`。
  - 返回 outcome。
- **若该单位无寒霜状态**：**清除** `FROST_IMMUNE`（免疫到期），返回 `{skip: false, move_cap: -1}`（正常）。

### 3.4 状态生命周期
- `FROST_SLOW / FROST_ROOT / FROST_FREEZE` = **回合级状态**：纳入 `clear_round_statuses`（`round_ended` 触发）——若目标在结算前死亡或因故未结算，回合末自清，不残留。
- `FROST_IMMUNE` = **跨回合状态**：**不**纳入 `clear_round_statuses`，生命周期完全由 `resolve_frost_for_turn` 管理（结算寒霜时置、无寒霜结算时清）。
- 免疫时序示例（敌 E，玩家每回合都打 E）：
  - 回合 N 我方阶段：命中 E → E 非免疫 → 施 FROST_x。
  - 回合 N 敌方阶段 E 回合：结算 → 受控（如冻结）+ 消费 FROST_x + 置 FROST_IMMUNE。
  - 回合 N 末 `round_ended`：清回合级状态（FROST_x 已消费；FROST_IMMUNE 保留）。
  - 回合 N+1 我方阶段：命中 E → E 免疫 → **跳过施加**。
  - 回合 N+1 敌方阶段 E 回合：无寒霜 → **清 FROST_IMMUNE** + 正常行动。
  - 回合 N+2：E 可再被冻。
  - ⇒ 同一敌人最多隔一回合冻一次，杜绝永冻。免疫即便该回合未被攻击也会在其下个回合到期。

### 3.5 整合（EnemyAI 感知寒霜）
- `EnemyAI._on_enemy_turn_started(unit_id)` 开头调 `var fr := _battle_resolution.resolve_frost_for_turn(unit_id)`：
  - `fr.skip == true`（冻结）→ 强制 WAIT：`mark_has_acted(unit_id)` + `EventBus.enemy_actions_completed.emit(unit_id)` 后 return（不 `decide_intent`、不移动不攻击）。
  - 否则把 `fr.move_cap`（-1 = `u.get_move_range()`，否则取该值）作为**有效移动范围**传入 `decide_intent` 的可达格计算（替代当前直接用 `u.get_move_range()` 的三处）。
- 这是本特性**唯一**需要修改 `EnemyAI` 的位置：`decide_intent` 参数化有效移动范围 + 回合开头寒霜短路。其余意图逻辑（目标选择、行为分支、攻击判定）不变。

### 3.6 纸娃娃描述
- 扩展 `SetEffectCatalog._DESC`，补 `set_frost` 各 {3,6,9}：`{3: "滞步", 6: "冰封", 9: "冻结"}`（纸娃娃逻辑已通用，补描述后自动显示✦行）。

## 4. 公式（Formulas）

- 施加：攻击者最高激活档 T ∈ {9,6,3} → 施 FROST_FREEZE / FROST_ROOT / FROST_SLOW（仅当目标非 FROST_IMMUNE）。
- 有效移动范围：SLOW → `floor(get_move_range() / 2)`；ROOT/FREEZE → `0`；正常 → `move_cap = -1` 表示用 `get_move_range()`。
- 跳过：FREEZE → `skip = true`（敌方 WAIT）。
- 免疫：结算寒霜后置 FROST_IMMUNE；无寒霜结算时清 FROST_IMMUNE。

## 5. 边界情况（Edge Cases）

- 目标已 FROST_IMMUNE：跳过施加（不挂新寒霜，不刷新免疫）。
- 目标在结算前死亡：`resolve_unit_downed` 已 `erase(unit_id)` 全状态（FROST_x + IMMUNE 一并清），无残留。
- 目标存活但回合内未被攻击：其回合结算走"无寒霜"分支 → 清 FROST_IMMUNE（若有），正常行动。
- 多次命中同一敌（双 crew 或普攻+斩）：各次都尝试施加；非免疫时重复置同一/最高档状态（幂等）；免疫时全跳过。
- damage==0 的命中（被 GUARDED/SET_GUARD 减半到 0）：仍触发施加（寒霜与本次伤害值无关）。
- 滞步 floor：move_range==1 时 `floor(1/2)=0` → 实际等同冰封（可接受，低移动敌被滞步即定身）。
- 寒霜误施于 crew（理论，敌方当前无装备）：crew 无 AI 回合、`resolve_frost_for_turn` 仅 EnemyAI 调用 → 该 crew 永不结算 → 状态回合末自清（无害空状态）。
- 9 档冻结的敌即便处于可攻击位也不攻击（FREEZE 优先于一切意图）。

## 6. 依赖（Dependencies）

- `SetBonus`（count_sets / is_tier_active）。
- `BattleResolution`（既有 apply_status / get_unit_status / _consume_status / clear_round_statuses / _unit_statuses / resolve_unit_downed；**新增** FROST_* 常量 + `resolve_frost_for_turn`）。
- `SetReactionSystem`（②b-2b；on_attack_executed 攻击者侧加寒霜分支）。
- `EnemyAI`（_on_enemy_turn_started 加寒霜短路；decide_intent 参数化有效移动范围）。
- `EventBus.attack_executed`（既有施加触发源）、`enemy_actions_completed`（既有，冻结短路复用）。
- `SetEffectCatalog`（②b-2a；扩 set_frost 描述）。
- **不依赖** RunManager。**不改** SetEffectSystem、_compute_attack_damage、伤害管线、PlayerTurnController。

## 7. 可调旋钮（Tuning Knobs）

- 三档效果映射（滞步=减半 / 冰封=0 / 冻结=跳过）；滞步的减半公式。
- 免疫时长（当前固定"下一回合"，由结算逻辑隐式控制）。
- 寒霜状态常量名 / 纸娃娃描述文案。

## 8. 验收标准（Acceptance Criteria）

- **AC-1（施加分档）**：攻击者持 set_frost 3/6/9 件，命中非免疫敌方 → 目标分别获 FROST_SLOW / FROST_ROOT / FROST_FREEZE（按最高激活档）。
- **AC-2（滞步）**：FROST_SLOW 敌 `resolve_frost_for_turn` 返回 `{skip:false, move_cap:floor(move/2)}` 并消费状态。
- **AC-3（冰封）**：FROST_ROOT 敌返回 `{skip:false, move_cap:0}` 并消费。
- **AC-4（冻结）**：FROST_FREEZE 敌返回 `{skip:true, ...}` 并消费；EnemyAI 据此强制 WAIT（不移动不攻击）。
- **AC-5（免疫防永冻）**：结算寒霜后目标获 FROST_IMMUNE；免疫期内再命中不施加；该敌下个回合无寒霜结算后免疫清除，可再次被冻。
- **AC-6（回合级清除）**：FROST_SLOW/ROOT/FREEZE 在 round_ended 被 clear_round_statuses 清除；FROST_IMMUNE 不被其清除。
- **AC-7（EnemyAI 有效移动范围）**：非冻结的受控敌（滞步/冰封）以 move_cap 为有效移动范围决策（可达格据此缩减），仍可在射程内攻击。
- **AC-8（纸娃娃）**：set_frost 各档在纸娃娃显示对应中文描述。
- **AC-9（装配+回归）**：全量 0 错误/失败/孤儿；SetEffectSystem / 伤害管线 / 既有 EnemyAI 意图逻辑行为不变。

## 9. 非目标（本期不做）

- 寒霜对**玩家单位**的冻结（需 PlayerTurnController 支持；敌方当前无装备，moot）。
- 寒霜层数/叠加（单一最高档状态，不累计）。
- 寒霜伤害（纯控制，不走 apply_reaction_damage）。
- 概率冻结（本作战斗逻辑确定性，无随机）。
- 难度系统 + 敌方按难度配装（另立子项目）。
- 寒霜的美术/音效/HUD 图标（视觉 ADVISORY，留后续）。
