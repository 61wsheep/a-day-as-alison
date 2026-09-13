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

## 与美工 / 文案的协作同步（多人向 main 推送）

### 核心不变量：每个文件只有一个写入者

破了这条，整套协作就退回「两份完整文件没法合并」的老问题——那正是场景拆分要解决的。

| 文件 | 唯一写入者 | 我方可否动 |
|---|---|---|
| `scenes/levels/*_terrain.tscn`、`alison_room_walls.tscn` | **美工** | ❌ 绝不动 |
| `scenes/levels/` 关卡场景（`plaza.tscn` 等） | 主程 | ✅ |
| `scripts/`、`resources/` | 主程 | ✅ |
| `assets/` 下的 PNG | **美工** | ❌ |
| 根目录设计文档 `.md` | 文案 / owner | — |

**要改地形 → 让美工改，或在关卡场景里改（摆装饰、加碰撞、挂脚本）。绝不要在 Godot 编辑器里打开 `*_terrain.tscn` 改东西。**

### 拉取流程（他们推上来之后）

**⚠️ 第 0 步不可省：先确认 Godot 编辑器已关闭。**

Godot 把场景装在内存里。编辑器开着时拉取，两种坏法都是**静默**的：

- 弹窗问「是否重新加载」时点「否」→ 之后任何一次保存都把**内存里的旧版写回磁盘**，静默覆盖美工的工作，而 `git status` 只会显示"你改过这个文件"
- 点「是」→ 编辑器里未保存的改动丢失

```bash
# 1. 确认工作区状态（export_presets.cfg 常年脏，可忽略）
git status

# 2. 先看再拉——范围不对就停下来问，别闷头合
git fetch origin
git log --oneline main..origin/main

# 3. 拉
git pull origin main

# 4. 重开 Godot 编辑器，等它重新导入素材

# 5. 验收（两条都要过）
../godot.windows.editor.x86_64.exe --headless --path . --script res://scripts/tools/check_scene_refs.gd
../godot.windows.editor.x86_64.exe --headless --path . scenes/tests/test_forage_spawn.tscn
```

**第 2 步是安全阀：** 正常只该出现 `*_terrain.tscn` 和 `assets/`。若出现关卡场景或 `scripts/`，说明美工误开了实例编辑，**先确认再拉**。

- **报 `invalid UID`** → 跑 `../godot.windows.editor.x86_64.exe --headless --path . --import` 重建 uid 缓存
- **真冲突了** → 按设计不该发生，说明有人越线。**不要在 Godot 里点「解决冲突」**，先 `git status` 看是哪个文件
- **文案的文档在 `docs/design` 分支** → 去另一个工作区拉：`cd D:/AIGameBuild-DesignDocs && git pull origin docs/design`

### 永远不提交

`export_presets.cfg` 的本地改动是别人在途的改动，**不提交**。`git add` 一律用**显式路径**，绝不用 `git add -A`。

## 初始化检查（每次会话开始）

1. 确认工作目录在 `d:\AIGameBuild`
2. 运行 `git branch --show-current` 确认当前分支
3. 运行 `git status` 确认工作区干净
4. 运行 `git fetch origin --quiet`，报告 `main` 与 `docs/design` 是否有远程新提交（有则提示走上面的拉取流程）

## Godot 项目信息

- 引擎：Godot **4.7** · 2D · GL Compatibility（以 `project.godot` 的 `features` 为准）
  - ⚠️ 磁盘上的 `godot.windows.editor.x86_64.exe` 是 **4.6.2 自定义构建**，**仅供 headless 跑测试与导出**，不是编辑器本体
  - 美工同学须装 **4.7.x 标准版**；用 4.6 打开会静默降级场景格式（见《美工 Git 协作规约 v0.2》）
- 项目路径：`d:\AIGameBuild\成为艾莉森的一天\`
- 入口场景：`scenes/main.tscn`
- Autoload：EventBus, GameManager, TimeManager
