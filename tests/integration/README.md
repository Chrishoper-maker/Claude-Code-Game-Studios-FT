# Integration Tests

跨系统与存档往返测试。一系统/一交互一子目录（如 `tests/integration/combat/`）。

- 用于多系统交互、信号链、save/load 一致性。
- 命名同单元测试：`[system]_[feature]_test.gd` / `test_[scenario]_[expected]`。
- 套件根类 `extends GdUnitTestSuite`；需要真实场景时用 `await` + `scene_runner()`。

（本文件同时作为占位，确保空目录纳入版本控制；落地首个集成测试后可删。）
