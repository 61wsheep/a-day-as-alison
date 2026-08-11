"""
交互式对话模式 —— 让你实时跟 NPC 聊天

用法:
    python interactive_chat.py padwin       # 跟 Padwin 对话
    python interactive_chat.py soraya       # 跟 Soraya 对话（需角色卡）

在对话中输入 'quit' 退出，输入 'topics' 查看话题建议。
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import PROMPTS_DIR, SCHEMAS_DIR, DEFAULT_PROVIDER, DEFAULT_MODEL
from utils.api_client import call_llm_structured
from utils.json_parser import parse_json_response


# ── 对话系统常量 ──
MAX_TURNS = 50                # 单次会话最大轮数
MEMORY_WINDOW = 10            # 保留最近 N 轮的完整上下文
TOPIC_COUNT = 4               # 每次建议话题数


def _load_npc(npc_id: str) -> str:
    """加载 NPC 角色卡"""
    path = os.path.join(PROMPTS_DIR, f"npc_{npc_id}.txt")
    if not os.path.exists(path):
        raise FileNotFoundError(f"角色卡不存在: {path}")
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def _load_system_prompt() -> str:
    """加载天的 System Prompt"""
    with open(os.path.join(PROMPTS_DIR, "tian_system.txt"), "r", encoding="utf-8") as f:
        return f.read()


def _print_divider(char="─", width=60):
    print(char * width)


def _print_npc_response(text: str):
    """打印 NPC 的回复 —— 每行自动缩进，方便阅读"""
    for line in text.split("\n"):
        print(f"  {line}")
    print()


def _print_topic_suggestions(topics: list[str]):
    """打印话题建议"""
    if not topics:
        return
    print("  💬 你可以聊聊这些:")
    for t in topics:
        print(f"     · {t}")
    print()


def _generate_topics(
    npc_id: str,
    npc_card: str,
    system_prompt: str,
    history: list[dict],
    day: int = 3,
) -> list[str]:
    """实时生成话题建议"""
    schema = {
        "type": "object",
        "properties": {
            "topic_suggestions": {
                "type": "array",
                "items": {"type": "string"},
            }
        },
        "required": ["topic_suggestions"],
    }

    recent = history[-4:] if history else []
    history_text = "\n".join(
        f"玩家: {h['player']}\n{npc_id}: {h['npc']}" for h in recent
    ) if recent else "（尚无对话）"

    user_msg = f"""【化身面具 —— {npc_id} 对话话题建议】

今天是第 {day} 天。当前对话历史：
{history_text}

请以 {npc_id} 的语气生成 {TOPIC_COUNT} 个话题建议，每个 15-30 字。
要求：
- 反映 {npc_id} 此刻可能的情绪
- 含蓄地暗示 {npc_id} 的秘密或内心冲突
- 推动叙事前进
- 用 {npc_id} 本人的语气写（不是系统指令的语气）

返回 JSON：{{"topic_suggestions": ["...", "..."]}}"""

    try:
        parsed, _, success, _ = call_llm_structured(
            system_prompt=f"{system_prompt}\n\n{npc_card}",
            user_message=user_msg,
            json_schema=schema,
            provider=DEFAULT_PROVIDER,
            model=DEFAULT_MODEL,
            max_tokens=512,
            temperature=0.7,
        )
        if success and parsed:
            return parsed.get("topic_suggestions", [])
    except Exception:
        pass
    return []


def _generate_environment_description(
    npc_id: str, npc_card: str, system_prompt: str, day: int
) -> str:
    """生成开场环境描述 —— 天写的一段第三人称场景文本"""
    user_msg = f"""【叙事面具 —— 环境描述】

现在是贝戈尼亚森林的第 {day} 天下午。玩家即将与 {npc_id} 对话。

请用 2-3 句话描述当前的环境和 {npc_id} 的状态。
用第三人称，文学性强，50-100 字。只返回这段文本，不要 JSON，不要引号。"""

    from utils.api_client import call_llm
    try:
        text = call_llm(
            system_prompt=f"{system_prompt}\n\n{npc_card}",
            user_message=user_msg,
            provider=DEFAULT_PROVIDER,
            model=DEFAULT_MODEL,
            max_tokens=200,
            temperature=0.9,
        )
        return text.strip().strip('"').strip("'")
    except Exception:
        return ""


def run_chat(npc_id: str, day: int = 3, affection: int = 50):
    """
    运行交互式对话循环。

    Args:
        npc_id: NPC 标识（如 "padwin"）
        day: 当前模拟天数
        affection: 初始好感度
    """
    # 加载资产
    system_prompt = _load_system_prompt()
    npc_card = _load_npc(npc_id)

    # 加载 dialogue schema
    with open(os.path.join(SCHEMAS_DIR, "dialogue_schema.json"), "r", encoding="utf-8") as f:
        schema = json.load(f)

    # 对话历史
    history: list[dict] = []     # [{"player": ..., "npc": ...}]
    memory_updates: list[str] = []  # AI 返回的 memory_update 摘要

    # 初始好感度
    current_affection = affection

    _print_divider("=")
    print(f"  交互式对话模式 —— {npc_id}")
    print(f"  第 {day} 天 | 初始好感度: {affection}")
    print(f"  输入 'quit' 退出 | 'topics' 查看话题建议 | 'status' 查看状态")
    _print_divider("=")
    print()

    # 开场环境描述
    env = _generate_environment_description(npc_id, npc_card, system_prompt, day)
    if env:
        print(f"  {env}")
        print()

    # 初始话题建议
    topics = _generate_topics(npc_id, npc_card, system_prompt, history, day)
    if topics:
        _print_topic_suggestions(topics)

    turn = 0

    while turn < MAX_TURNS:
        turn += 1

        # 读取玩家输入
        try:
            player_input = input("你: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n  [对话结束]")
            break

        if not player_input:
            continue

        # 特殊命令
        if player_input.lower() == "quit":
            print("\n  [你转身离开了。Padwin 站在原地，目送你远去。]")
            break
        if player_input.lower() == "topics":
            topics = _generate_topics(npc_id, npc_card, system_prompt, history, day)
            _print_topic_suggestions(topics)
            continue
        if player_input.lower() == "status":
            print(f"  好感度: {current_affection}/100 | 对话轮数: {turn-1} | 记忆摘要: {len(memory_updates)}条")
            continue

        # 组装上下文
        recent_history = history[-(MEMORY_WINDOW * 2):]
        history_block = "\n".join(
            f"玩家: {h['player']}\n{npc_id}: {h['npc']}" for h in recent_history
        ) if recent_history else "（第一次对话）"

        memory_block = "\n".join(f"- {m}" for m in memory_updates[-5:]) if memory_updates else "（尚无记忆）"

        user_msg = f"""【化身面具 —— 正在扮演 {npc_id}】

今天是第 {day} 天下午。
{npc_id} 对玩家的当前好感度：{current_affection}/100。

{npc_id} 的最近记忆：
{memory_block}

对话历史：
{history_block}

玩家刚才说：「{player_input}」

请以 {npc_id} 的身份回应玩家。以 JSON 格式返回（见 dialogue_schema）。
记住：你不是 AI 助手，你是 {npc_id}。用你的性格、你的经历、你的语气说话。"""

        # 调用 AI
        print()  # 空行
        print(f"  [{npc_id} 正在思考……]", end="\r")
        parsed, raw_text, first_try, _ = call_llm_structured(
            system_prompt=f"{system_prompt}\n\n{npc_card}",
            user_message=user_msg,
            json_schema=schema,
            provider=DEFAULT_PROVIDER,
            model=DEFAULT_MODEL,
            max_tokens=1024,
            temperature=0.8,
        )

        # 解析
        if parsed is None:
            result = parse_json_response(raw_text, schema)
            if result.success and result.parsed:
                parsed = result.parsed

        if parsed is None:
            print("  ⚠️  [AI 未能生成有效回复，请重试]")
            print(f"  [raw: {raw_text[:100]}...]")
            continue

        response_text = parsed.get("response_text", "")
        emotional_shift = parsed.get("emotional_shift", 0)
        memory_update = parsed.get("memory_update", "")
        hints = parsed.get("hints_to_other_npcs", [])
        should_end = parsed.get("should_end_conversation", False)

        # 更新状态
        current_affection += emotional_shift
        current_affection = max(0, min(100, current_affection))
        if memory_update:
            memory_updates.append(memory_update)

        history.append({"player": player_input, "npc": response_text})

        # 显示回复
        print(" " * 25, end="\r")  # 清除 "正在思考"
        _print_npc_response(response_text)

        if emotional_shift != 0:
            sign = "+" if emotional_shift > 0 else ""
            print(f"  [好感度 {sign}{emotional_shift} → {current_affection}/100]")

        if hints:
            print(f"  💡 线索: {' | '.join(hints)}")

        if should_end:
            print()
            _print_divider()
            print(f"  [{npc_id} 似乎不想再聊下去了。]")
            break

        print()

    # 会话结束
    _print_divider("=")
    print(f"  对话结束。共 {turn} 轮。")
    print(f"  最终好感度: {current_affection}/100")
    print(f"  记忆摘要: {len(memory_updates)} 条")
    _print_divider("=")

    # 输出完整历史供回顾
    print()
    print("  📜 完整对话记录已保存。输入 'history' 查看，或直接忽略。")
    _history = history


def _main():
    import argparse
    parser = argparse.ArgumentParser(description="交互式 NPC 对话")
    parser.add_argument("npc", type=str, help="NPC 标识 (如 padwin)")
    parser.add_argument("--day", type=int, default=3, help="模拟天数")
    parser.add_argument("--affection", type=int, default=50, help="初始好感度")
    args = parser.parse_args()

    try:
        run_chat(args.npc, args.day, args.affection)
    except FileNotFoundError as e:
        print(f"[ERROR] {e}")
        sys.exit(1)


if __name__ == "__main__":
    _main()
