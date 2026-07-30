"""
V3: 塔罗解读文学质量验证

5 张牌 × 3 种玩家处境 = 15 条预言诗。
人工评分维度：诗意度、模糊度、呼应度、独特性（1-5 分）。

运行：
cd /d/AIGameBuild/ai_verify
python run_all.py --v3

"""

import json
import os
import time
from datetime import datetime

from config import (
    PROMPTS_DIR, SCHEMAS_DIR, FIXTURES_DIR, RESULTS_DIR,
    V3_TAROT_CARDS, V3_CONTEXTS_PER_CARD, DEFAULT_PROVIDER, DEFAULT_MODEL,
)
from utils.api_client import call_llm_structured
from utils.json_parser import parse_json_response, safe_get


def _load_assets():
    """加载 Prompt 资产"""
    with open(os.path.join(PROMPTS_DIR, "tian_system.txt"), "r", encoding="utf-8") as f:
        system_prompt = f.read()
    with open(os.path.join(PROMPTS_DIR, "tarot_cards.json"), "r", encoding="utf-8") as f:
        tarot_cards = json.load(f)
    with open(os.path.join(SCHEMAS_DIR, "oracle_schema.json"), "r", encoding="utf-8") as f:
        schema = json.load(f)
    with open(os.path.join(FIXTURES_DIR, "player_contexts.json"), "r", encoding="utf-8") as f:
        contexts = json.load(f)

    return system_prompt, tarot_cards, schema, contexts


def run_v3(provider: str = DEFAULT_PROVIDER, model: str = DEFAULT_MODEL) -> dict:
    """
    运行 V3 验证：塔罗解读文学质量。

    Returns:
        验证结果字典
    """
    print("─" * 60)
    print("  V3: 塔罗解读文学质量验证")
    print(f"  5 张牌 × 3 种语境 = 15 条预言诗")
    print("─" * 60)

    system_prompt, tarot_cards, schema, contexts = _load_assets()

    # 选取 3 种代表性语境
    selected_contexts = [
        {"id": "day1_new_player", "label": "第 1 天 · 纯新手"},
        {"id": "day7_suspicious", "label": "第 7 天 · 多疑玩家"},
        {"id": "day12_tense", "label": "第 12 天 · 张力高峰"},
    ]

    context_map = {}
    for ctx in contexts:
        context_map[ctx["id"]] = ctx

    results = []
    total_calls = 0
    total_json_failures = 0

    for card in tarot_cards[:V3_TAROT_CARDS]:
        card_name = card["name"]
        print(f"\n  ▸ {card_name} ({card['name_en']})")

        for ctx_meta in selected_contexts:
            ctx = context_map.get(ctx_meta["id"])
            if not ctx:
                continue

            user_msg = f"""【天命面具 —— 塔罗预言】

当前抽到的牌：{card_name} ({card['name_en']})，正位。

玩家处境：
- 第 {ctx['day_number']} 天
- benevolence = {ctx['benevolence']}
- engagement = {ctx['engagement']}
- truth_proximity = {ctx['truth_proximity']}
- NPC 关系：Soraya={ctx['npc_affection']['soraya']}, Padwin={ctx['npc_affection']['padwin']}, Bishop={ctx['npc_affection']['cactus_bishop']}

请为今日生成 3-5 句塔罗预言诗。以 JSON 格式返回（见 oracle_schema）。"""

            t0 = time.time()
            parsed, raw_text, first_try, _ = call_llm_structured(
                system_prompt=system_prompt,
                user_message=user_msg,
                json_schema=schema,
                provider=provider,
                model=model,
            )
            elapsed = time.time() - t0

            total_calls += 1

            prophecy_lines = []
            tone = ""
            json_ok = False

            if parsed is not None:
                json_ok = True
                prophecy_lines = safe_get(parsed, "prophecy", [])
                tone = safe_get(parsed, "tone", "unknown")
            else:
                total_json_failures += 1
                # 尝试恢复
                result = parse_json_response(raw_text, expected_schema=schema)
                if result.success and result.parsed:
                    json_ok = True
                    prophecy_lines = safe_get(result.parsed, "prophecy", [])
                    tone = safe_get(result.parsed, "tone", "unknown")

            prophecy_text = "\n".join(prophecy_lines) if prophecy_lines else "[无输出]"

            results.append({
                "card": card_name,
                "context": ctx_meta["label"],
                "day": ctx["day_number"],
                "tone": tone,
                "prophecy": prophecy_lines,
                "json_valid": json_ok,
                "latency_s": round(elapsed, 1),
                "raw_snippet": raw_text[:200] if raw_text else "",
            })

            status = "✓" if json_ok else "✗"
            snippet = prophecy_lines[0][:40] + "..." if prophecy_lines else "[空]"
            print(f"     {status} {ctx_meta['label']}: {snippet}")

    # 生成人工评分文件
    output_dir = os.path.join(RESULTS_DIR, datetime.now().strftime("%Y%m%d_%H%M%S"))
    os.makedirs(output_dir, exist_ok=True)

    review_lines = ["# V3 塔罗解读文学质量 —— 人工评分\n\n"]
    review_lines.append("请对以下 15 条预言诗进行 1-5 分评分。\n\n")
    review_lines.append("评分维度：\n")
    review_lines.append("- **诗意度 (1-5)**: 是否有文学质感（不是大白话、模板填空）\n")
    review_lines.append("- **模糊度 (1-5)**: 是否足够模糊，允许多种应验方式\n")
    review_lines.append("- **呼应度 (1-5)**: 是否呼应了当前玩家处境\n")
    review_lines.append("- **独特性 (1-5)**: 与其他牌 × 语境的组合是否有区分度\n\n")
    review_lines.append("---\n\n")

    for i, r in enumerate(results):
        review_lines.append(f"## {i+1}. {r['card']} — {r['context']}\n\n")
        review_lines.append(f"**语调**: {r['tone']} | **JSON 合法**: {'是' if r['json_valid'] else '否'}\n\n")
        for line in r["prophecy"]:
            review_lines.append(f"> {line}\n")
        review_lines.append("\n")
        review_lines.append("| 维度 | 评分 (1-5) | 备注 |\n")
        review_lines.append("|------|-----------|------|\n")
        review_lines.append("| 诗意度 | [ ] | |\n")
        review_lines.append("| 模糊度 | [ ] | |\n")
        review_lines.append("| 呼应度 | [ ] | |\n")
        review_lines.append("| 独特性 | [ ] | |\n")
        review_lines.append("\n---\n\n")

    review_path = os.path.join(output_dir, "v3_human_review.md")
    with open(review_path, "w", encoding="utf-8") as f:
        f.writelines(review_lines)

    # 计算自动指标
    json_success_rate = (total_calls - total_json_failures) / total_calls * 100

    print(f"\n  ── V3 自动指标 ──")
    print(f"  总调用: {total_calls} | JSON 成功率: {json_success_rate:.1f}%")
    print(f"  [NOTE] V3 的核心评判标准是人工评分，自动指标为辅助参考")
    print(f"  人工评分文件: {review_path}")
    print(f"  请独立评分后汇总平均分。通过标准: 平均分 > 3.0/5")

    return {
        "name": "v3",
        "passed": None,  # 需要人工评分后才能确定
        "json_success_rate": json_success_rate,
        "total_cards": V3_TAROT_CARDS,
        "total_samples": len(results),
        "human_review_file": review_path,
        "results": results,
    }
