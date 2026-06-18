# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 49 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Language / 语言规范

**全部对话和反馈必须使用中文。** 包括：与用户的所有交流、问题与选项、草稿讲解、
评审意见、状态汇报、子代理返回的总结。代码标识符、文件名、引擎 API 名称保持英文；
设计文档正文以中文为主（章节标题可保留英文模板格式）。

## Technology Stack

- **Engine**: Godot 4.6.3
- **Language**: GDScript
- **Version Control**: Git with trunk-based development
- **Build System**: SCons (engine), Godot Export Templates
- **Asset Pipeline**: Godot Import System + custom resource pipeline

> **Note**: Engine-specialist agents exist for Godot, Unity, and Unreal with
> dedicated sub-specialists. Use the set matching your engine.

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

@docs/engine-reference/godot/VERSION.md

## Technical Preferences

@.claude/docs/technical-preferences.md

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- No commits without user instruction
- **交互规范：永远只向用户呈现选项（AskUserQuestion），不要求用户自由输入文字。**
  所有确认、裁决、反馈均通过选项按钮完成。
- **用户交互提醒：每次调用 AskUserQuestion 之前，先执行 Bash 命令发送 macOS 系统通知：**
  ```
  osascript -e 'display notification "需要您做出选择" with title "Claude Code" sound name "Ping"'
  ```
  目的：用户在后台时通过系统通知+音效获知需要操作。

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

@.claude/docs/context-management.md
