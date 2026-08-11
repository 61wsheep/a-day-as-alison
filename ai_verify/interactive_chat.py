"""
交互式对话模式 —— 让你实时跟 NPC 聊天

用法:
    python interactive_chat.py padwin              # 跟 Padwin 对话（自动加载上次记忆）
    python interactive_chat.py padwin --reset      # 全新对话，清除历史记忆
    python interactive_chat.py padwin --verbose    # 显示 AI 内部推理（结束判断/好感度逻辑）

在对话中输入:
    quit      退出（自动保存记忆）
    topics    查看话题建议
    status    查看好感度、轮数、记忆条数
    history   查看本次对话的完整记录
"""

import json
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import PROMPTS_DIR, SCHEMAS_DIR, DEFAULT_PROVIDER, DEFAULT_MODEL
from utils.api_client import _sanitize_dict, _sanitize_str

# ── 常量 ──
MAX_TURNS = 50                # 硬上限：单次会话绝对最大轮数
MIN_TURNS = 5                 # 软下限：前 N 轮 AI 不能主动结束对话
MEMORY_WINDOW = 10            # 保留最近 N 轮的完整上下文
TOPIC_COUNT = 4               # 每次建议话题数
MEMORY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "memories")


# ── 记忆持久化 ──

def _memory_path(npc_id: str) -> str:
    return os.path.join(MEMORY_DIR, f"{npc_id}.json")


def _load_memory(npc_id: str) -> dict:
    """
    从磁盘加载 NPC 的跨会话记忆。
    返回: {"day": int, "affection": int, "memory_updates": [...], "total_turns": int}
    如果文件不存在或损坏，返回默认值。
    """
    path = _memory_path(npc_id)
    if not os.path.exists(path):
        return {"day": 1, "affection": 50, "memory_updates": [], "total_turns": 0}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, KeyError):
        return {"day": 1, "affection": 50, "memory_updates": [], "total_turns": 0}


def _save_memory(npc_id: str, day: int, affection: int, memory_updates: list[str],
                 total_turns: int, history: list[dict]):
    """保存 NPC 的跨会话记忆到磁盘"""
    os.makedirs(MEMORY_DIR, exist_ok=True)
    data = _sanitize_dict({
        "npc_id": npc_id,
        "last_saved": datetime.now().isoformat(),
        "day": day + 1,
        "affection": affection,
        "memory_updates": memory_updates[-20:],
        "total_turns": total_turns + len(history),
        "recent_history": [
            {"player": h["player"], "npc": h["npc"]}
            for h in history[-3:]
        ] if history else [],
    })
    with open(_memory_path(npc_id), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _reset_memory(npc_id: str):
    """清除 NPC 的记忆"""
    path = _memory_path(npc_id)
    if os.path.exists(path):
        os.remove(path)


def _save_history_markdown(npc_id: str, history: list[dict], day: int, affection_start: int,
                           affection_end: int, memory_updates: list[str]):
    """保存完整对话记录为可读 Markdown 文件"""
    os.makedirs(MEMORY_DIR, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = os.path.join(MEMORY_DIR, f"{npc_id}_history_{ts}.md")

    lines = [
        f"# {npc_id} 对话记录",
        f"日期: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"第 {day} 天 | 好感度: {affection_start} -> {affection_end}",
        f"轮数: {len(history)}",
        "",
        "---",
        "",
    ]

    for i, h in enumerate(history, 1):
        lines.append(f"### 第 {i} 轮")
        lines.append(f"**你:** {h['player']}")
        lines.append(f"**{npc_id}:** {h['npc']}")
        if h.get("emotional_shift"):
            sign = "+" if h["emotional_shift"] > 0 else ""
            lines.append(f"*好感度 {sign}{h['emotional_shift']}*")
        if h.get("memory_update"):
            lines.append(f"*记忆: {h['memory_update']}*")
        if h.get("internal_note"):
            lines.append(f"*内心: {h['internal_note']}*")
        lines.append("")

    lines.append("---")
    lines.append(f"记忆摘要 ({len(memory_updates)} 条):")
    for m in memory_updates:
        lines.append(f"- {m}")

    with open(path, "w", encoding="utf-8") as f:
        f.write(_sanitize_str("\n".join(lines)))

    return path


# ── Prompt 加载 ──

def _load_npc(npc_id: str) -> str:
    path = os.path.join(PROMPTS_DIR, f"npc_{npc_id}.txt")
    if not os.path.exists(path):
        raise FileNotFoundError(f"角色卡不存在: {path}")
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def _load_system_prompt() -> str:
    with open(os.path.join(PROMPTS_DIR, "tian_system.txt"), "r", encoding="utf-8") as f:
        return f.read()


# ── UI 工具 ──

def _print_divider(char="-", width=60):
    print(char * width)


def _print_npc_response(text: str):
    for line in text.split("\n"):
        print(f"  {line}")
    print()


def _print_topic_suggestions(topics: list[str]):
    if not topics:
        return
    print("  你可以聊聊这些:")
    for t in topics:
        print(f"     · {t}")
    print()


# ── 话题建议生成 ──

def _generate_topics(
    npc_id: str, npc_card: str, system_prompt: str,
    history: list[dict], memory_updates: list[str], day: int,
) -> list[str]:
    schema = {
        "type": "object",
        "properties": {"topic_suggestions": {"type": "array", "items": {"type": "string"}}},
        "required": ["topic_suggestions"],
    }

    recent = history[-4:] if history else []
    history_text = "\n".join(
        f"玩家: {h['player']}\n{npc_id}: {h['npc']}" for h in recent
    ) if recent else "（尚无对话）"

    memory_text = ", ".join(memory_updates[-3:]) if memory_updates else "（尚无跨天记忆）"

    user_msg = f"""【指定面具 —— {npc_id} 对话话题建议】

第 {day} 天。{npc_id} 的跨天记忆: {memory_text}
当前对话:
{history_text}

请以 {npc_id} 的语气生成 {TOPIC_COUNT} 个话题建议，每个 15-30 字。
反映当前情绪，暗示人物秘密或内心冲突，推动叙事。用 {npc_id} 本人的语气写。
返回 JSON: {{"topic_suggestions": ["...", "..."]}}"""

    try:
        from utils.api_client import call_llm_structured
        parsed, _, success, _ = call_llm_structured(
            system_prompt=f"{system_prompt}\n\n{npc_card}",
            user_message=user_msg, json_schema=schema,
            provider=DEFAULT_PROVIDER, model=DEFAULT_MODEL,
            max_tokens=512, temperature=0.7,
        )
        if success and parsed:
            return parsed.get("topic_suggestions", [])
    except Exception:
        pass
    return []


# ── 环境描述 ──

def _generate_environment_description(
    npc_id: str, npc_card: str, system_prompt: str, day: int,
    memory_updates: list[str],
) -> str:
    mem_text = ", ".join(memory_updates[-3:]) if memory_updates else ""
    user_msg = f"""【叙事面具 —— 环境描述】

贝戈尼亚森林第 {day} 天下午。{npc_id} 的跨天记忆线索: {mem_text or '无'}。
请用 2-3 句话描述环境与 {npc_id} 的状态。第三人称，50-100 字。只返回文本，不要 JSON。"""

    from utils.api_client import call_llm
    try:
        text = call_llm(
            system_prompt=f"{system_prompt}\n\n{npc_card}",
            user_message=user_msg, provider=DEFAULT_PROVIDER, model=DEFAULT_MODEL,
            max_tokens=200, temperature=0.9,
        )
        return text.strip().strip('"').strip("'")
    except Exception:
        return ""


# ── 核心对话循环 ──

def run_chat(npc_id: str, day: int = None, affection: int = None,
             *, reset: bool = False, verbose: bool = False):
    """
    运行交互式对话循环。

    Args:
        npc_id: NPC 标识
        day: 模拟天数（None = 从记忆加载，首次 = 1）
        affection: 初始好感度（None = 从记忆加载，首次 = 50）
        reset: 清除跨会话记忆，重新开始
        verbose: 显示 AI 内部推理（结束判断/好感度逻辑/internal_note）
    """
    # ── 记忆管理 ──
    if reset:
        _reset_memory(npc_id)
        print(f"  [记忆已重置] {npc_id} 恢复到初始状态")
        print()

    saved = _load_memory(npc_id)
    if day is None:
        day = saved["day"]
    if affection is None:
        affection = saved["affection"]
    memory_updates: list[str] = saved.get("memory_updates", [])
    total_turns_before = saved.get("total_turns", 0)

    # ── 加载资产 ──
    system_prompt = _load_system_prompt()
    npc_card = _load_npc(npc_id)
    with open(os.path.join(SCHEMAS_DIR, "dialogue_schema.json"), "r", encoding="utf-8") as f:
        schema = json.load(f)

    history: list[dict] = []
    current_affection = affection

    # 如果有上次对话的记忆片段，注入到开场环境
    if memory_updates:
        saved_history = saved.get("recent_history", [])
        if saved_history:
            history = saved_history  # 把上次最后 3 轮带入当前对话上下文

    _print_divider("=")
    print(f"  交互式对话模式 —— {npc_id}")
    print(f"  第 {day} 天 | 初始好感度: {current_affection}/100")
    if total_turns_before > 0:
        print(f"  跨天记忆: {len(memory_updates)} 条摘要 (累计 {total_turns_before} 轮对话)")
    if verbose:
        print(f"  [verbose 模式: 显示 AI 内部推理]")
    print(f"  输入 'quit' 退出 | 'topics' 话题 | 'status' 状态 | 'history' 历史")
    _print_divider("=")
    print()

    # 开场环境
    env = _generate_environment_description(
        npc_id, npc_card, system_prompt, day, memory_updates)
    if env:
        print(f"  {env}")
        print()

    # 初始话题建议
    topics = _generate_topics(npc_id, npc_card, system_prompt, history, memory_updates, day)
    if topics:
        _print_topic_suggestions(topics)

    turn = 0

    while turn < MAX_TURNS:
        turn += 1

        try:
            player_input = input("你: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n  [对话结束]")
            break

        if not player_input:
            continue

        # ── 特殊命令 ──
        if player_input.lower() == "quit":
            print(f"\n  [你转身离开了。{npc_id} 目送你远去。]")
            break

        if player_input.lower() == "topics":
            topics = _generate_topics(
                npc_id, npc_card, system_prompt, history, memory_updates, day)
            _print_topic_suggestions(topics)
            continue

        if player_input.lower() == "status":
            print(f"  天数: {day} | 好感度: {current_affection}/100")
            print(f"  本轮对话: {turn-1} 轮 | 跨天累计: {total_turns_before + turn - 1} 轮")
            print(f"  跨天记忆摘要: {len(memory_updates)} 条")
            continue

        if player_input.lower() == "history":
            if not history:
                print("  (暂无对话记录)")
            else:
                for i, h in enumerate(history, 1):
                    print(f"  [{i}] 你: {h['player']}")
                    print(f"  [{i}] {npc_id}: {h['npc']}")
                    if h.get("emotional_shift"):
                        sign = "+" if h["emotional_shift"] > 0 else ""
                        print(f"      好感 {sign}{h['emotional_shift']}")
                    print()
            continue

        # ── 组装 AI 上下文 ──
        recent = history[-(MEMORY_WINDOW * 2):]
        history_block = "\n".join(
            f"玩家: {h['player']}\n{npc_id}: {h['npc']}" for h in recent
        ) if recent else "（第一次对话）"

        # 跨天记忆
        cross_day_block = "\n".join(
            f"- {m}" for m in memory_updates[-5:]
        ) if memory_updates else "（尚无跨天记忆 —— 今天是你们第一次见面）"

        user_msg = f"""【化身面具 —— 正在扮演 {npc_id}】

第 {day} 天下午。{npc_id} 对玩家的好感度: {current_affection}/100。

跨天记忆（之前几天的对话摘要 —— NPC 可能隐隐约约有印象，但不一定主动提起）:
{cross_day_block}

本轮对话历史:
{history_block}

玩家刚才说: [{player_input}]

以 {npc_id} 的身份回应（JSON）。记住:
- 你是 {npc_id} —— 用你的性格、经历、语气说话，你不是 AI 助手
- 这是今天第 {turn} 轮对话，如果感觉对话该结束了，设 should_end_conversation=true"""

        # ── 调用 AI ──
        print()
        print(f"  [{npc_id} 正在思考……]", end="\r")
        from utils.api_client import call_llm_structured
        parsed, raw_text, first_try, _ = call_llm_structured(
            system_prompt=f"{system_prompt}\n\n{npc_card}",
            user_message=user_msg, json_schema=schema,
            provider=DEFAULT_PROVIDER, model=DEFAULT_MODEL,
            max_tokens=1024, temperature=0.8,
        )

        # 解析
        if parsed is None:
            result = parse_json_response(raw_text, schema)
            if result.success and result.parsed:
                parsed = result.parsed

        if parsed is None:
            print("  [!] [AI 未能生成有效回复，请重试]")
            if verbose:
                print(f"  [raw text: {raw_text[:200]}...]")
            continue

        response_text = parsed.get("response_text", "")
        emotional_shift = parsed.get("emotional_shift", 0)
        memory_update = parsed.get("memory_update", "")
        internal_note = parsed.get("internal_note", "")
        hints = parsed.get("hints_to_other_npcs", [])
        should_end = parsed.get("should_end_conversation", False)

        # ── 最小轮数保护 —— 前 MIN_TURNS 轮不允许 AI 结束对话 ──
        if should_end and turn <= MIN_TURNS:
            if verbose:
                print(f"  [verbose] AI 想结束对话，但被 MIN_TURNS({MIN_TURNS}) 阻止")
            should_end = False

        # 更新状态
        current_affection += emotional_shift
        current_affection = max(0, min(100, current_affection))
        if memory_update:
            memory_updates.append(memory_update)

        history.append({
            "player": player_input,
            "npc": response_text,
            "emotional_shift": emotional_shift,
            "internal_note": internal_note,
            "memory_update": memory_update,
        })

        # 显示回复
        print(" " * 25, end="\r")
        _print_npc_response(response_text)

        if emotional_shift != 0:
            sign = "+" if emotional_shift > 0 else ""
            print(f"  [好感度 {sign}{emotional_shift} -> {current_affection}/100]")

        # ── verbose: 显示 AI 内部推理 ──
        if verbose:
            if internal_note:
                print(f"  [内心] {internal_note}")
            if memory_update:
                print(f"  [记忆] {memory_update}")
            print(f"  [结束判断] AI 设为 {should_end} | 当前轮数 {turn}/{MIN_TURNS} (最小 {MIN_TURNS} 轮)")

        if hints:
            print(f"  [线索] {' | '.join(hints)}")

        if should_end:
            print()
            _print_divider()
            print(f"  [{npc_id} 似乎不想再聊下去了。]")
            break

        print()

    # ── 会话结束：保存 ──
    _print_divider("=")
    print(f"  对话结束。本轮 {turn} 轮。")
    print(f"  最终好感度: {current_affection}/100  (起始: {affection})")
    print(f"  跨天记忆: {len(memory_updates)} 条 (本次新增 {len(memory_updates) - len(saved.get('memory_updates', []))} 条)")
    _print_divider("=")

    # 保存跨会话记忆
    _save_memory(npc_id, day, current_affection, memory_updates,
                 total_turns_before, history)
    print(f"  记忆已保存 -> {_memory_path(npc_id)}")

    # 保存可读历史
    md_path = _save_history_markdown(
        npc_id, history, day, affection, current_affection, memory_updates)
    print(f"  对话记录已保存 -> {md_path}")


# ── 入口 ──

def _main():
    import argparse
    parser = argparse.ArgumentParser(description="交互式 NPC 对话")
    parser.add_argument("npc", type=str, help="NPC 标识 (如 padwin)")
    parser.add_argument("--day", type=int, default=None, help="模拟天数 (默认从记忆加载)")
    parser.add_argument("--affection", type=int, default=None, help="初始好感度 (默认从记忆加载)")
    parser.add_argument("--reset", action="store_true", help="清除跨天记忆，重新开始")
    parser.add_argument("--verbose", action="store_true", help="显示 AI 内部推理")
    args = parser.parse_args()

    try:
        run_chat(args.npc, args.day, args.affection,
                 reset=args.reset, verbose=args.verbose)
    except FileNotFoundError as e:
        print(f"[ERROR] {e}")
        sys.exit(1)


if __name__ == "__main__":
    _main()
