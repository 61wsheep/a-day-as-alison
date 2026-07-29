# CLAUDE.md —— 《成为艾莉森的一天》项目工作流

> 本文件在每次会话启动时自动加载。以下规则为强制性约束。

---

## 分支结构（强制执行）

```
main          → 游戏开发（Godot 项目代码、场景、资源、脚本）
docs/design   → 设计文档（策划案、AI 机制、工作内容、技术草稿等 Markdown）
feat/xxx      → 功能分支（从 main 切出，合并回 main）
```

## 分支选择规则（硬性约束）

**在每次执行 Write/Edit 操作之前，必须根据修改内容自动切换到正确分支：**

| 修改内容 | 必须所在分支 |
|---------|------------|
| `成为艾莉森的一天/` 目录下的任何文件（.gd, .tscn, .tres, .png, .svg, .import, .godot, .editorconfig, .gitattributes, .gitignore, .mcp.json, .vscode/, .codebuddy/, assets/, scenes/, scripts/, resources/, export_templates/, feature_profiles/, script_templates/, text_editor_themes/） | `main` |
| 仓库根目录的设计文档（AI机制点子集.md, Demo开发计划.md, M4_系统设计_技术草稿.md, *策划案*.md, *工作内容*.md 等 .md 文件） | `docs/design` |
| 仓库根目录的工程文件（.code-workspace, .gitignore） | `main` |

**规则：**
1. **写入前检查**：在调用 Write/Edit 之前，先 `git branch --show-current` 确认当前分支是否正确。如不正确，先切换分支再写入。
2. **禁止跨线混合**：绝对不在 `main` 上写设计文档，绝对不在 `docs/design` 上写游戏代码。
3. **提交信息规范**：使用约定式提交格式。
   - `main`：`feat:` / `fix:` / `refactor:` / `chore:` + 中文描述
   - `docs/design`：`docs:` + 中文描述

## 日常工作流

```
写代码   → git checkout main → 开发 → git add + commit
写文档   → git checkout docs/design → 编辑 → git add + commit
大功能   → git checkout -b feat/功能名 (从 main 切) → PR/MR 方式合并回 main
里程碑   → git tag -a v0.1.0 -m "描述" (在 main 上打)
```

## 初始化检查（每次会话开始）

1. 确认工作目录在 `d:\AIGameBuild`
2. 运行 `git branch --show-current` 确认当前分支
3. 运行 `git status` 确认工作区干净

## Godot 项目信息

- 引擎：Godot 4.6 · 2D · GL Compatibility
- 项目路径：`d:\AIGameBuild\成为艾莉森的一天\`
- 入口场景：`scenes/main.tscn`
- Autoload：EventBus, GameManager, TimeManager
