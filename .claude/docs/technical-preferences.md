# Technical Preferences

<!-- Populated by /setup-engine. Updated as the user makes decisions throughout development. -->
<!-- All agents reference this file for project-specific standards and conventions. -->

## Engine & Language

- **Engine**: Godot 4.6.3
- **Language**: GDScript
- **Rendering**: Forward+ (PC desktop; 风格化低模 3D 小场景 + 2D 分镜演出层)
- **Physics**: Godot Physics 3D (built-in; 网格战棋，物理使用极少)

## Input & Platform

<!-- Written by /setup-engine. Read by /ux-design, /ux-review, /test-setup, /team-ui, and /dev-story -->
<!-- to scope interaction specs, test helpers, and implementation to the correct input methods. -->

- **Target Platforms**: PC (Steam / Epic)
- **Input Methods**: Keyboard/Mouse (primary), Gamepad (partial)
- **Primary Input**: Keyboard/Mouse（战棋类标准操作）
- **Gamepad Support**: Partial（网格光标导航可后期适配，非 MVP 范围）
- **Touch Support**: None
- **Platform Notes**: 网格战棋以鼠标点选为主；所有 UI 须支持键盘快捷键；悬停提示不可承载关键信息（兼容未来手柄适配）

## Naming Conventions

- **Classes**: PascalCase (e.g., `CrewMember`, `BondGauge`)
- **Variables**: snake_case (e.g., `bond_charge`, `grid_position`)
- **Signals/Events**: snake_case 过去式 (e.g., `bond_gauge_filled`, `crew_recruited`)
- **Files**: snake_case 与类名对应 (e.g., `crew_member.gd`)
- **Scenes/Prefabs**: PascalCase 与根节点对应 (e.g., `CrewMember.tscn`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_CREW_SIZE`)

## Performance Budgets

- **Target Framerate**: 60 fps
- **Frame Budget**: 16.6 ms
- **Draw Calls**: < 500（2D 战棋单屏，含爆发演出峰值）
- **Memory Ceiling**: < 1 GB

## Testing

- **Framework**: GdUnit4 — 经 AssetLib 安装到 `addons/gdUnit4/`；脚手架与 CI 由 /test-setup 生成（2026-06-18 定，与 /test-setup 技能本体及 coding-standards 一致）
- **Minimum Coverage**: 逻辑系统（羁绊效果矩阵、伤害公式、回合状态机）必须有单元测试；覆盖率目标 70%
- **Required Tests**: Balance formulas, gameplay systems, networking (if applicable — 本作无网络)

## Forbidden Patterns

<!-- Add patterns that should never appear in this project's codebase -->
- [None configured yet — add as architectural decisions are made]

## Allowed Libraries / Addons

<!-- Add approved third-party dependencies here -->
- [None configured yet — add as dependencies are approved]

## Architecture Decisions Log

<!-- Quick reference linking to full ADRs in docs/architecture/ -->
- [No ADRs yet — use /architecture-decision to create one]

## Engine Specialists

<!-- Written by /setup-engine when engine is configured. -->
<!-- Read by /code-review, /architecture-decision, /architecture-review, and team skills -->
<!-- to know which specialist to spawn for engine-specific validation. -->

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist (all .gd files)
- **Shader Specialist**: godot-shader-specialist (.gdshader files, VisualShader resources)
- **UI Specialist**: godot-specialist (no dedicated UI specialist — primary covers all UI)
- **Additional Specialists**: godot-gdextension-specialist (GDExtension / native C++ bindings only)
- **Routing Notes**: Invoke primary for architecture decisions, ADR validation, and cross-cutting code review. Invoke GDScript specialist for code quality, signal architecture, static typing enforcement, and GDScript idioms. Invoke shader specialist for material design and shader code. Invoke GDExtension specialist only when native extensions are involved.

### File Extension Routing

<!-- Skills use this table to select the right specialist per file type. -->
<!-- If a row says [TO BE CONFIGURED], fall back to Primary for that file type. -->

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (.gd files) | godot-gdscript-specialist |
| Shader / material files (.gdshader, VisualShader) | godot-shader-specialist |
| UI / screen files (Control nodes, CanvasLayer) | godot-specialist |
| Scene / prefab / level files (.tscn, .tres) | godot-specialist |
| Native extension / plugin files (.gdextension, C++) | godot-gdextension-specialist |
| General architecture review | godot-specialist |
