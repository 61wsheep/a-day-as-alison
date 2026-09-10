# Dialogue Lab —— AI 对话探针（离游戏）

《成为艾莉森的一天》的**独立 Python 对话探针**：不改游戏工程，就能测 prompt、量延迟、验证上下文分层/缓存值不值。

## 它做什么

读引擎**同一批**源文件并**逐字复刻**引擎的拼装逻辑（`ai_dialogue_session.gd::_build_payload`），直连同一 SiliconFlow 端点：

- `ai/tian_system.txt` + `ai/npc_<id>.txt`（system 层）
- `ai/dialogue_schema.json`（schema 注入层）

对同一段玩家脚本，用不同配置各打一遍，输出 **延迟（首字/全文）/ token / 缓存命中 / 回复** 对照。

## 配置开关（回答的问题）

| 配置 | 回答 |
|---|---|
| `baseline`（非流式，默认） | 引擎现状：全文生成完才返回 → 20s 的基线 |
| `stream`（流式） | 上流式后**首字延迟**降到多少 → 决定要不要改 AIBridge |
| `cachetest`（同文连打 2 遍） | SiliconFlow/DeepSeek 认不认稳定前缀缓存 → 上下文分层值多少 prefill |

prompt 措辞调参：改 `state` / `script` / 卡文本后重跑，直观看语气与 OOC。

## 用法

```bash
python dialogue_lab.py --dry          # 只拼装 + token 量级，不发网络（验拼装）
python dialogue_lab.py                # 默认矩阵 baseline + stream + cachetest
python dialogue_lab.py --configs baseline   # 只跑某一配置
python dialogue_lab.py --max-tokens 256     # 覆盖输出限幅（提速实验）
python dialogue_lab.py --npc soraya         # 换角色卡
python dialogue_lab.py --no-heaven          # user 消息去掉"天的注视"层
```

key 解析顺序：`SILICONFLOW_API_KEY` 环境变量 → `--key` → Godot `user://ai_api_key.txt`（Windows appdata，自动读）。

纯标准库，无第三方依赖。

## 输出

- 控制台对照表：每轮 OK/FAIL、首字延迟、全文延迟、prompt tok、缓存 hit/miss、出 tok、回复摘录
- `runs/report_<时间戳>.json`：完整结构化报告（含逐轮完整回复 JSON）

## 与引擎的关系

探针只**读**游戏文件、**不改**任何游戏工程文件。引擎未来若改拼装口径，需同步这里（拼装函数在 `dialogue_lab.py::build_payload`，已注明对应引擎函数与逐字复刻）。
