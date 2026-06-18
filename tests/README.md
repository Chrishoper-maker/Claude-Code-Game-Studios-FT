# Test Infrastructure

**Engine**: Godot 4.6.3
**Test Framework**: GdUnit4（经 AssetLib 安装到 `addons/gdUnit4/`）
**CI**: `.github/workflows/tests.yml`
**Setup date**: 2026-06-18（/test-setup，B4）

## Directory Layout

```
tests/
  unit/           # 隔离单元测试（公式 / 状态机 / 逻辑），一系统一子目录
  integration/    # 跨系统与存档往返测试
  smoke/          # 关键路径清单（/smoke-check 的 15 分钟人工门控）
  evidence/       # 截图日志与人工测试签字记录
```

## 安装 GdUnit4（首次，一次性）

```
1. 编辑器 → AssetLib → 搜 "gdUnit4" → Download & Install
2. 启用插件：Project → Project Settings → Plugins → gdUnit4 ✓
3. 重启编辑器
4. 核实：res://addons/gdUnit4/ 存在
```

> ⚠️ 需要仓库根存在 `project.godot`（生产工程）。当前仅原型有工程；根工程在实现阶段建立后，
> 测试与 CI 才会真正运行（CI 有 guard，未就绪时空跑通过）。原型 `prototypes/` 不纳入 CI。

## 运行测试

```bash
# 全部测试（无头）。★ 全新 clone 须先 --import 生成全局类名缓存，否则 class_name 报 "Could not find type"
godot --headless --import
# --ignoreHeadlessMode：GdUnit4 默认拒绝无头（退出 103）；纯逻辑测试不碰 UI/输入，安全跳过
godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests
```

编辑器内：打开 gdUnit4 面板（底部 dock）→ 选目录/套件 → Run。

## Test Naming

- **文件**：`[system]_[feature]_test.gd`
- **函数**：`test_[scenario]_[expected]`
- **示例**：`combat_damage_test.gd` → `test_base_attack_returns_expected_damage()`
- 套件根类：`extends GdUnitTestSuite`

## Story Type → Test Evidence

| Story Type | Required Evidence | Location |
|---|---|---|
| Logic | 自动单元测试——必须通过 | `tests/unit/[system]/` |
| Integration | 集成测试 OR 试玩文档 | `tests/integration/[system]/` |
| Visual/Feel | 截图 + lead 签字 | `tests/evidence/` |
| UI | 人工走查 OR 交互测试 | `tests/evidence/` |
| Config/Data | 烟测通过 | `production/qa/smoke-*.md` |

## CI

每次 push 到 `main` 与每个 PR 自动运行；测试失败即阻断合并。
CI 在跑测试前**必先 `--import`**（`.godot/` 是 gitignore 的，每次全新 clone 都需重建全局类名缓存）。
