# 《成为艾莉森的一天》30分钟 Demo 开发计划

> **版本：** v1.1 | **日期：** 2026-07-28 | **目标平台：** PC (Godot 4.6) | **游戏类型：** 2D 俯视角 RPG
>
> **v1.1 修订说明：** 技术方案由 3D 第一人称修正为 2D 俯视角 RPG（`Node2D` / `TileMap` / `Sprite2D` / `CharacterBody2D`）。

---

## 一、现状差距分析

### 1.1 已具备

| 类别 | 内容 | 完整度 |
|------|------|--------|
| 游戏设计 | 策划案（世界观、角色、情节曲线、22结局概要） | ✅ 完整 |
| 系统设计 | 10大系统详细规则 + 依赖关系 + AI集成方案 | ✅ 完整 |
| 项目骨架 | `project.godot`、Godot 4.6 引擎、MCP 开发工具链 | ✅ 就绪 |
| 开发技能 | 9 个 CodeBuddy 技能（代码生成、场景格式、文档搜索等） | ✅ 就绪 |
| 版本控制 | Git 仓库已初始化，首轮提交完成 | ✅ 就绪 |

### 1.2 完全缺失（Demo 必须补齐）

| 缺失项 | 说明 | Demo 优先级 |
|--------|------|-------------|
| **所有场景文件 (.tscn)** | 没有任何场景 | 🔴 P0 |
| **所有脚本 (.gd)** | 没有任何 GDScript | 🔴 P0 |
| **2D 美术素材** | 地形图块集（TileSet）、角色/NPC 精灵图、道具图标 | 🔴 P0 |
| **UI 界面** | 对话框、选项面板、HUD | 🔴 P0 |
| **角色控制器** | 俯视角 WASD 移动（`CharacterBody2D`） | 🔴 P0 |
| **对话系统实现** | LLM API 调用 + 对话树 | 🔴 P0 |
| **时间循环逻辑** | 时间段推进 + 重置 | 🔴 P0 |
| **音频** | 背景音乐、音效 | 🟡 P1（可用无音效替代） |
| **存档系统** | 跨循环数据保留 | 🟡 P1（Demo 可暂用内存） |
| **草药合成系统** | UI + 随机合成逻辑 | 🟢 P2（Demo 可裁剪） |

### 1.3 结论

项目目前是 **100% 的设计文档 + 0% 的可运行代码**。Demo 需要从零搭建全部游戏系统。

---

## 二、Demo 范围定义："可玩的叙事切片"

### 2.1 目标体验（~30 分钟）

```
玩家醒来 → 遇见索拉雅 → 探索森林（2个区域）→ 赚金币租树屋
→ 与 1-2 个 NPC 深度对话 → 触发石巢塔楼事件
→ 回答"猜猜我是谁"→ 达成结局 → 循环回到清晨
```

### 2.2 裁剪原则

> Demo 不是删减版，而是**垂直切片**——把一条完整的叙事线做深，而非把所有系统做浅。

| 系统 | 完整版目标 | Demo 裁剪 |
|------|-----------|----------|
| NPC 数量 | 15 个 | **3 个**（索拉雅、帕德温、卡克特斯主教） |
| 地图区域 | 5 个 | **3 个**（广场/引导区、树屋区、石巢塔楼） |
| 结局数量 | 22 个 | **3 个**（愚人、女祭司、节制） |
| 赚钱方式 | 5 种 | **1 种**（采集蘑菇 + 塔罗占卜服务） |
| 对话 AI | LLM 实时生成 | **预写文本 + 1 个 LLM 接入点**作为 PoC |
| 草药合成 | AI 动态生成 | **Demo 不实现**，改为直接采集出售 |
| 学历系统 | 多学科进修 | **Demo 不实现** |
| 好感度 UI | 数值面板 | **无 UI**，仅内存追踪，影响对话选项出现 |

### 2.3 Demo 结局设计

| 结局 | 塔罗牌 | 触发条件 | 预计玩到时 |
|------|--------|---------|-----------|
| **愚人** | The Fool | 线索不足，在塔楼错认"天"是主教 | 第一轮最自然的结果 |
| **女祭司** | The High Priestess | 逼问索拉雅 + 帮助她觉醒 | 第二轮的探索线 |
| **节制** | Temperance | 不妄下判断，在塔楼中搜索 | 第三轮的探索线 |

三轮循环 ≈ 10 分钟/轮 ≈ 总计 30 分钟。玩家能自然体验时间循环机制和"选择改变结局"的核心乐趣。

---

## 三、技术架构

### 3.1 场景结构

```
res://
├── scenes/
│   ├── main.tscn                    # 入口场景（Autoload 初始化）
│   ├── game.tscn                    # 游戏主场景
│   ├── levels/
│   │   ├── plaza.tscn               # 森林广场（初始区域，索拉雅引导）
│   │   ├── treehouse_district.tscn  # 树屋住宅区（帕德温/卡克特斯）
│   │   └── stone_nest_tower.tscn    # 石巢塔楼（高潮/结局场景）
│   └── ui/
│       ├── dialogue_ui.tscn         # 对话界面（选项框 + NPC 文本）
│       ├── hud.tscn                 # HUD（时间段、金币、当日塔罗牌）
│       └── tarot_ui.tscn            # 每日抽牌界面
├── scripts/
│   ├── autoload/
│   │   ├── game_manager.gd          # 全局游戏状态（跨循环数据）
│   │   ├── time_manager.gd          # 时间推进（事件驱动）
│   │   └── event_bus.gd             # 全局信号总线
│   ├── player/
│   │   └── player_controller.gd     # 俯视角角色控制器（CharacterBody2D）
│   ├── npc/
│   │   ├── npc_base.gd              # NPC 基类
│   │   ├── soraya.gd                # 索拉雅（引导 + 女祭司线）
│   │   ├── padwin.gd                # 帕德温（恋人线触发）
│   │   └── cactus_bishop.gd         # 卡克特斯主教（愚人线触发）
│   ├── systems/
│   │   ├── dialogue_system.gd       # 对话逻辑
│   │   ├── ending_judge.gd          # 结局判定逻辑
│   │   └── tarot_system.gd          # 塔罗牌抽牌 + 运势
│   └── ui/
│       ├── dialogue_ui.gd
│       ├── hud.gd
│       └── tarot_ui.gd
├── resources/
│   ├── dialogues/                    # 预写对话 JSON
│   │   ├── soraya_intro.json
│   │   ├── padwin_tomato.json
│   │   ├── cactus_discovery.json
│   │   └── tower_midnight.json
│   ├── endings/                      # 结局条件 JSON
│   │   ├── fool.json
│   │   ├── high_priestess.json
│   │   └── temperance.json
│   └── tarot/
│       └── major_arcana.json         # 22 张牌定义
└── assets/
    ├── sprites/                      # 角色/NPC/道具 精灵图
    ├── tilesets/                     # 地形图块集（TileSet）
    └── audio/                        # 音频（后续补充）
```

### 3.2 2D 技术栈说明

> Demo 采用 Godot 4.6 原生 2D 管线，不依赖 3D 渲染器。

| 层 | 技术选型 | 说明 |
|----|---------|------|
| 渲染器 | `gl_compatibility` | 2D 性能最优，兼容性最广 |
| 场景根节点 | `Node2D` | 所有场景使用 2D 坐标系 |
| 玩家/NPC | `CharacterBody2D` + `Sprite2D` | 带碰撞的 2D 角色 |
| 地图 | `TileMap` + `TileSet` | 网格瓦片地图 |
| 摄像机 | `Camera2D` | 跟随玩家移动 |
| 碰撞检测 | `Area2D` / `CollisionShape2D` | 触发区域、对话检测 |
| UI | `Control` + `CanvasLayer` | 对话面板、HUD、塔罗界面 |
| 精灵尺寸规范 | 32×32 (图块) / 64×64 (角色) | 俯视角 RPG 标准规格 |

### 3.3 坐标与层级规范

| 概念 | 规范 |
|------|------|
| 图块大小 | **32×32 px**（TileMap 基础单元） |
| 角色精灵 | **64×64 px**（占 2×2 图块） |
| NPC 精灵 | **64×64 px**（与玩家一致） |
| 渲染层级 (z_index) | 地面 0 → 物品 1 → 角色 2 → 树冠 3 → UI 100 |
| Camera2D | 正交投影，平滑跟随（`drag_horizontal_enabled` / `drag_vertical_enabled`） |

### 3.4 Autoload 单例

| 单例名 | 脚本 | 职责 |
|--------|------|------|
| `GameManager` | `game_manager.gd` | 金币、已解锁结局、NPC好感度、已发现线索（跨循环保留） |
| `TimeManager` | `time_manager.gd` | 当前时间段、推进触发、重置逻辑 |
| `EventBus` | `event_bus.gd` | 全局信号（时间段变化、结局触发、NPC对话完成等） |

### 3.5 数据流

```
玩家交互 → NPC/物体 → EventBus 信号
                         ↓
                    GameManager 更新状态
                    TimeManager 检查时间推进条件
                         ↓
                    UI 层刷新
                         ↓
                [午夜] → EndingJudge 判定结局 → 播结局叙事 → 循环重置
```

---

## 四、分步开发计划（7 天）

### 第 1 天：项目地基搭建 🏗️

**目标：** 能从编辑器运行一个空场景

| 任务 | 产出 | 预估 |
|------|------|------|
| 1.1 创建 `main.tscn` 入口场景 | 根节点 `Node2D` + `Camera2D` | 30 min |
| 1.2 搭建 3 个 Autoload 单例 | `GameManager`, `TimeManager`, `EventBus` | 30 min |
| 1.3 实现 `GameManager` 数据结构 | 金币、好感度、结局列表、线索字典 | 30 min |
| 1.4 实现 `TimeManager` 基础逻辑 | 5 个时间段枚举 + `advance_time()` 方法 | 30 min |
| 1.5 实现 `EventBus` 信号定义 | 6-8 个核心信号 | 15 min |

**🔑 第一步就是：** 用 MCP 工具创建 `main.tscn` + 三个 Autoload `.gd` 文件。

---

### 第 2 天：角色控制器 + 基础场景 🚶

**目标：** 能在森林广场里走动

| 任务 | 产出 | 预估 |
|------|------|------|
| 2.1 创建 `PlayerController` | `CharacterBody2D` + WASD 八向移动 + `Camera2D` 跟随 | 1 h |
| 2.2 搭建 `plaza.tscn`（广场） | `TileMap` 铺地面 + 树木/装饰 `Sprite2D` | 1 h |
| 2.3 实现场景切换 | `Area2D` 触发器区域 → 切换场景 | 30 min |
| 2.4 搭建 `treehouse_district.tscn` | 树屋群 + 帕德温/卡克特斯的位置 | 1 h |
| 2.5 搭建 `stone_nest_tower.tscn` | 塔楼内部 + 神秘氛围 | 1 h |

---

### 第 3 天：对话系统 + 索拉雅引导线 💬

**目标：** 玩家能与 NPC 对话，索拉雅引导流程完整

| 任务 | 产出 | 预估 |
|------|------|------|
| 3.1 创建 `dialogue_ui.tscn` | NPC 文本 + 选项按钮 | 1 h |
| 3.2 实现 `DialogueSystem` | 加载 JSON → 显示对话 → 处理选项 | 2 h |
| 3.3 编写索拉雅引导对话 JSON | 见面 → 科普 → 给地图 → 离开 | 1 h |
| 3.4 创建索拉雅 NPC 场景 | 占位精灵图 + `CollisionShape2D` + 对话触发 | 1 h |
| 3.5 实现 `npc_base.gd` | 基础 NPC 交互（接近触发/点击触发） | 1 h |

---

### 第 4 天：经济 + 帕德温/卡克特斯线 💰

**目标：** 能赚金币租树屋，遇到第二个 NPC

| 任务 | 产出 | 预估 |
|------|------|------|
| 4.1 创建采集交互物 | 地面蘑菇/浆果 → 点击采集 → 入背包 | 1.5 h |
| 4.2 创建树屋管理员 NPC | 对话 → 支付金币 → 租房成功 | 1 h |
| 4.3 实现帕德温 NPC + 番茄试探对话 | 番茄过敏细节 | 1.5 h |
| 4.4 实现卡克特斯 NPC + 勒痕发现 | 主教自缢线索 | 1 h |
| 4.5 创建 HUD UI | 时间段、金币数、塔罗牌图标 | 1 h |

---

### 第 5 天：塔罗系统 + 石巢塔楼高潮 🔮

**目标：** 每日抽牌 → 推进到夜晚 → 塔楼场景

| 任务 | 产出 | 预估 |
|------|------|------|
| 5.1 实现 `TarotSystem` | 22 张牌数据 + 随机抽 + 运势等级 | 1.5 h |
| 5.2 创建 `tarot_ui.tscn` | 抽牌动画 + 运势文本 | 1 h |
| 5.3 实现时间推进触发条件 | 租房完成 → 推进到下午 → 塔楼入口激活 | 1 h |
| 5.4 搭建塔楼内部交互 | "猜猜我是谁" 对话节点 | 1.5 h |
| 5.5 实现 3 个选项分支 | 回答"主教" / "索拉雅" / "不回答" | 1 h |

---

### 第 6 天：结局判定 + 跨循环保留 🔄

**目标：** 一个结局能触发，循环能跑通

| 任务 | 产出 | 预估 |
|------|------|------|
| 6.1 实现 `EndingJudge` | 读取结局 JSON → 条件匹配 → 播结局 | 2 h |
| 6.2 编写 3 个结局定义 JSON | 愚人 / 女祭司 / 节制 | 1 h |
| 6.3 实现循环重置逻辑 | 回到清晨 → 保留数据 → 重置地形 | 2 h |
| 6.4 实现跨循环 NPC 记忆 | 索拉雅第二轮对话改变 | 1 h |
| 6.5 创建结局过渡动画 | 黑屏 + 塔罗牌面展示 + 叙事文本 | 1.5 h |

---

### 第 7 天：LLM 接入 PoC + 打磨 🎨

**目标：** 至少 1 个 NPC 接入 AI 对话，Demo 可从头玩到尾

| 任务 | 产出 | 预估 |
|------|------|------|
| 7.1 接入 Claude API | 索拉雅对话转为 LLM 生成 | 2 h |
| 7.2 实现 LLM 对话的选项生成 | 从 LLM 响应中解析选项 | 1.5 h |
| 7.3 完整 Demo 走通测试 | 从头到尾 → 达成 3 个结局 | 1.5 h |
| 7.4 Bug 修复 + 打磨 | 对话节奏、时间触发时机 | 1 h |
| 7.5 打包导出 | Windows 可执行文件 | 30 min |

---

## 五、现在可以做的第一步

### ✅ 已完成的准备工作

| 已完成 | 说明 |
|--------|------|
| `project.godot` 2D 配置 | 移除 Jolt Physics 3D + Forward Plus，渲染器设为 `gl_compatibility` |
| 版本 v1.1 修订 | 场景结构、技术选型全部切换为 2D 节点体系 |

### 🔑 第 1 步：搭建项目骨架（预计 1-1.5 小时）

具体要做的事：

1. **创建 2D 资产目录** — `assets/sprites/`、`assets/tilesets/`、`scenes/`、`scripts/` 等
2. **创建 Autoload 脚本** — 3 个 `.gd` 文件 + 在 `project.godot` 中注册
3. **创建 `main.tscn`** — 根节点 `Node2D` + `Camera2D`
4. **验证** — 在 Godot 编辑器中运行，确认场景无报错

### 可以立刻开始的 6 个具体动作：

```
动作 0: 创建 2D 目录结构（用 mkdir）
         res://assets/sprites/    ← 角色/NPC/道具精灵图
         res://assets/tilesets/   ← TileMap 图块集
         res://scenes/levels/     ← 关卡场景
         res://scenes/ui/         ← UI 场景
         res://scripts/autoload/  ← Autoload 单例
         res://scripts/player/    ← 玩家控制器
         res://scripts/npc/       ← NPC 脚本
         res://scripts/systems/   ← 游戏系统
         res://scripts/ui/        ← UI 脚本
         res://resources/dialogues/ ← 对话 JSON
         res://resources/endings/  ← 结局条件 JSON
         res://resources/tarot/    ← 塔罗牌数据

动作 1: 用 magicai_create_scene_tree 创建 res://scenes/main.tscn
         └── Node2D (root)
             └── Camera2D (摄像机, current=true, smoothing_enabled=true)

动作 2: 用 magicai_write_file 创建 res://scripts/autoload/event_bus.gd
         └── 定义 8 个信号: time_changed, gold_changed, dialogue_started,
             dialogue_ended, clue_found, ending_triggered, loop_reset, day_started

动作 3: 用 magicai_write_file 创建 res://scripts/autoload/game_manager.gd
         └── 数据结构: gold, endings_unlocked, clues_found, npc_affection 字典

动作 4: 用 magicai_write_file 创建 res://scripts/autoload/time_manager.gd
         └── 5 个时间段枚举 + advance_time() + 跨循环重置

动作 5: 用 magicai_set_project_settings 注册 3 个 Autoload 单例
         （EventBus → event_bus.gd, GameManager → game_manager.gd,
          TimeManager → time_manager.gd）
```

---

## 六、风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| LLM API 延迟影响对话体验 | 中 | 高 | 预写对话为主，LLM 仅做 PoC；加 loading 动画 |
| 角色控制器开发耗时超预期 | 中 | 中 | 使用 Godot 内置 `CharacterBody2D` 模板加速 |
| 时间循环重置逻辑出 Bug | 高 | 中 | 第 6 天预留 2h debug 时间 |
| 2D 美术素材缺乏导致观感差 | 高 | 低 | 明确这是 Demo，用纯色/占位图（ColorRect、占位贴图），后期替换 |
| 30 分钟游玩时长不足 | 中 | 中 | 设计时每轮循环目标 10 分钟，3 轮 = 30 分钟 |

---

## 七、Demo 完成标准（Checklist）

- [ ] 玩家能进入游戏，在俯视角 2D 画面中自由移动
- [ ] 能在 3 个区域之间切换
- [ ] 能与 3 个 NPC 对话（索拉雅、帕德温、卡克特斯），选项式分支
- [ ] 对话选项会根据之前的选择/线索而变化
- [ ] 能通过采集蘑菇赚取金币并租到树屋
- [ ] 每日清晨触发塔罗牌抽牌
- [ ] 时间推进到午夜后触发石巢塔楼场景
- [ ] 3 个结局至少各有一条路径可达
- [ ] 结局触发后正确循环回到清晨，保留数据（高塔结局除外）
- [ ] NPC 在后续循环中保有记忆/对话变化
- [ ] 至少 1 个 NPC 的对话接入 Claude API 实时生成
- [ ] 游玩时长 ≥ 30 分钟

---

> **下一步：** 确认此计划后，我将立即从第 1 步开始，创建 `main.tscn` 和 3 个 Autoload 脚本。
