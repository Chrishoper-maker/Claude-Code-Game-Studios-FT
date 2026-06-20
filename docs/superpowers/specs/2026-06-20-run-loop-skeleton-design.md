# 设计规格：可玩 run 循环骨架（子项目 A）

> Status: Approved（brainstorming 2026-06-20）
> 目标：把单场战斗扩成一局完整肉鸽 run——启动出航→部署→战斗→胜利→三选一招募→下一岛→…→run 终局，
> 并清掉 BattleScene 里的临时 hack（硬编码自动部署、断开 RunManager）。白盒（图元+Control）。
> 引擎 Godot 4.6.3 / GDScript。route-recruitment-system GDD（Approved）为权威。
> 上层 epic 拆解：A=本骨架；B=DeployScreen 手动选人；C=元层打磨。本 spec 仅 A。

## Overview

RunManager 已有 run 阶段状态机 + `run_phase_changed` 发射 + 场景切换钩子，但招募 offer 逻辑、roster 填充、
失败处理是 TODO，且无 RouteScene。本子项目落实这些纯逻辑 + 建白盒 RouteScene 中枢 + 让 BattleScene 按
run roster 部署，使整条 run 串起来。**不含战斗逻辑**（战斗已完成）。

## 流程与入口

`main_scene` 改为 **RouteScene**（战斗之间的中枢）。RouteScene `_ready` 按 `RunManager.current_phase` 分支：
- **IDLE**（启动首次进入）→ `RunManager.start_run()`（roster 填 starting crew）→ `confirm_deploy(roster ids)` → goto_battle（ISLAND_0，无招募）。
- **RECRUITING**（上一场胜利后 goto_route 回到此）→ 显示**白盒三选一卡** → 玩家点选 → `confirm_recruit(id)` → `confirm_deploy(roster ids)` → goto_battle。
- **RUN_END** → run-end 画面（"出航成功!"/"全员阵亡…" + [重新出航]→start_run 重来）。

战斗胜利/失败由 RunManager 既有/新增订阅驱动场景流转（见下）。**暂不做主菜单**（启动即出航；主菜单留 C）。

## RunManager 招募/流转逻辑（落实 TODO，纯逻辑可测）

新增成员：`_excluded_offers: Array[String]`（本 run 落选 unit_id）、`pending_deploy: Array[CrewDefinition]`（本场出场名单）。

- **`start_run()`**：清 roster/_excluded_offers/_downed_this_run/pending_deploy；roster 填入所有
  `recruit_pool_tier=="starting"` 的 CrewDefinition（经 `UnitDataManager.get_all_units()` 过滤）；island_index=-1；→ RUN_DEPLOYING。
- **`get_recruit_offers() -> Array[CrewDefinition]`**（GDD Rule 1-2 / R1 公式）：
  - 可用池 = 所有 `recruit_pool_tier=="pool"` 的 crew，排除 `unit_id ∈ roster` 与 `unit_id ∈ _excluded_offers`。
    （A 暂不含 `"unlockable"` tier——悬赏系统未做；A 暂不排除 `_downed_this_run`——永久死亡留后续，见范围边界。）
  - 无放回随机抽 ≤3 名，且**三名 unit_class 互不相同**（某职业可用不足 1 名时豁免该约束）。
  - 可用池 < 3 → 返回实际数量；= 0 → 返回空（RouteScene 据此跳过招募直接部署下一岛）。
  - 随机用 RunManager 持有的 `RandomNumberGenerator`（测试可 seed；单测断言不变量而非具体身份）。
- **`confirm_recruit(unit_id: String)`**：选中 crew 加入 roster；**本次该批其余候选**加入 `_excluded_offers`；→ RUN_DEPLOYING。
  （RunManager 须记住"本批候选" → 加成员 `_last_offers: Array[String]`，get_recruit_offers 时写入。）
- **`confirm_deploy(selected_ids: Array)`**：把 roster 中 id ∈ selected_ids 的 CrewDefinition 存入 `pending_deploy`；
  island_index += 1；→ RUN_ISLAND_BATTLE；`SceneManager.goto_battle()`。
- **`get_pending_deploy() -> Array[CrewDefinition]`**：供 BattleScene 读出场名单。
- **失败处理（新增）**：`_ready` 中 `EventBus.battle_lost.connect(_on_battle_lost)`；`_on_battle_lost()` → RUN_END +
  `EventBus.run_completed.emit(false, current_island_index + 1, roster.duplicate())`。
- 既有 `_on_battle_won`：保留（非末岛→RECRUITING+goto_route；末岛→RUN_END+run_completed(true)）。

## BattleScene 部署改为 roster 驱动

- 删 `_BOOTSTRAP_CREW`/`_BOOTSTRAP_CELLS` 与 `_deploy_starting_crew()`。
- 新增 `_deploy_run_crew()`：读 `RunManager.get_pending_deploy()` → 取前 N 个，按 `_valid_deploy_cells`（经 BattleMap）
  顺序自动排位 → `_battle_map.deploy_crew(defs, positions)`。N = min(pending.size(), 可用 deploy 格数)。
  （A 全员自动部署，忽略 DEPLOY_LIMIT；DEPLOY_LIMIT+手动选归 B。）
- 删 BattleScene 里"断开 RunManager._on_battle_won"的 TEMP（route_scene 存在后不再崩）。
- **BattleResultOverlay 退出 run 流程**：从 BattleScene.tscn 移除 BattleResultOverlay 节点 + battle_scene.gd 的
  `@onready _battle_result_overlay` 引用 + 其 `setup()` 调用（保留 `src/ui/battle_result_overlay.gd` 文件，留作未来单场/调试）。
  胜利→招募、失败→run-end 由 RunManager+RouteScene 接管。

## RouteScene（新场景 + 脚本，白盒）

- `scenes/RouteScene.tscn`（Control 根 + 脚本 `src/ui/route_scene.gd`）+ 在 SceneManager autoload 的 `route_scene` 导出赋值（project.godot），并把 `main_scene` 改为 RouteScene。
- `_ready` 按 `RunManager.current_phase` 分支（见流程）。RECRUITING 分支：调 `get_recruit_offers()`，为每个候选建一个 Button
  显示「职业名 · display_name · battle_cry」（不显数值，GDD），点击 → `confirm_recruit(id)` 然后 `confirm_deploy(roster ids)`。
  候选为空 → 直接 `confirm_deploy(roster ids)`（跳过招募）。RUN_END 分支：显示结果 + [重新出航]。
- 自动部署辅助：RouteScene 收集 `RunManager.get_roster()` 的 unit_id 列表传给 confirm_deploy（A 全员）。

## 数据：补 pool crew

补足 `recruit_pool_tier=="pool"` 的 CrewDefinition .tres（现仅 2：双刀·岚 swordsman、炮手·卡农 gunner），
新增 ~6 个覆盖缺失职业，使三选一有真实选择、roster 能朝 6 精英羁绊对成长：
- 至少各 1：medic（医师）、navigator（航海士）、musician（乐手）；再补 bulwark、swordsman/gunner 各 1。
- 数值取 unit-data 强度带；class_action_id 用动词名（slash/guard/cannon/heal/displace/aura）；battle_cry ≤24 字。

## 测试策略

**BLOCKING 单测**（tests/unit/run_manager/）：
- start_run：roster == 所有 starting crew；_excluded_offers/island_index 重置；phase==DEPLOYING。
- get_recruit_offers：① 全为 pool tier ② 不含 roster 内 unit_id ③ 不含 _excluded_offers ④ ≤3 ⑤ 三者 unit_class 互不相同
  ⑥ 可用<3 返回实际数 ⑦ 可用=0 返回空。（注入 seed 保证确定；断言不变量。）
- confirm_recruit：选中入 roster；其余候选入 _excluded_offers；phase==DEPLOYING。
- confirm_deploy：pending_deploy == 选中 defs；island_index++；phase==BATTLE。
- battle_lost → RUN_END + run_completed(false,...)；battle_won 非末岛 → RECRUITING；末岛 → RUN_END + run_completed(true,...)。
- pool crew .tres 校验（ResourceLoader：类型 CrewDefinition、tier=="pool"、字段齐）。
- 测试隔离：RunManager 是 autoload（全局单态）→ 单测须在 before/after 保存恢复其状态，或用独立实例（若可 new）。
  RunManager 无 class_name（autoload）→ 单测用 `RunManager`（autoload 名）直接操作并在 after_test 调 start_run 复位 + 断开本测试连接。

**ADVISORY F5**：RouteScene 三选一卡、run-end 画面、整条 run（出航→打→招募→下一岛→…→终局）串通；胜利不崩。

## 范围边界（YAGNI，留 B/C 或更后）

- DeployScreen 手动选人 + DEPLOY_LIMIT（A 全员自动部署）→ B。
- **船员永久死亡**（downed crew 移出 roster + 排除招募）→ 后续（涉 battle_id:int↔unit_id:String 跨场景映射，A 不做；A 里阵亡 crew 下场仍"复活"）。
- unlockable tier / 悬赏解锁系统（#14）→ 更后。
- 阵亡通知卡、run-end 美化、主菜单/出航入口、portrait/美术 → C。
- 存档系统 → 更后。

## 验收标准

- **AC-1**：启动游戏 → 自动开 run，roster=阿斩+梅莉，直接进 ISLAND_0 战斗（这两人已部署在场）。
- **AC-2**：打赢一场（非末岛）→ 进 RouteScene，显示 3 张候选卡（职业·名·台词，职业互不相同）。
- **AC-3**：点一张候选 → 该 crew 入队 → 进下一岛战斗，场上能看到新队员（roster 增长生效）。
- **AC-4**：连打到第 5 岛（ISLAND_COUNT_MAX）打赢 → run-end "出航成功!" + [重新出航]。
- **AC-5**：任一场打输 → run-end "全员阵亡…" + [重新出航]；不再因航线跳转崩溃。
- **AC-6**：[重新出航] → start_run 重来，回到 ISLAND_0。
- **AC-7**：招募候选池抽干（可用=0）时跳过招募直接进下一岛，不崩。
