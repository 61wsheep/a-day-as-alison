"""
V1: JSON 结构化输出可靠性验证

验证三个面具（天命/化身/审判）的结构化 JSON 输出稳定性。
每种面具调用 30 次，每次用不同 context，统计解析成功率。
"""

import json
import os
import time
from datetime import datetime

from config import (
    PROMPTS_DIR, SCHEMAS_DIR, FIXTURES_DIR, RESULTS_DIR,
    V1_ITERATIONS, DEFAULT_PROVIDER, DEFAULT_MODEL,
)
from utils.api_client import call_llm_structured
from utils.json_parser import parse_json_response, safe_get
from utils.scorer import VerificationReport, ScoreCard


def _load_prompts():
    """加载 Prompt 资产"""
    with open(os.path.join(PROMPTS_DIR, "tian_system.txt"), "r", encoding="utf-8") as f:
        system_prompt = f.read()
    return system_prompt


def _load_schemas():
    """加载三个面具的 JSON Schema"""
    with open(os.path.join(SCHEMAS_DIR, "oracle_schema.json"), "r", encoding="utf-8") as f:
        oracle = json.load(f)
    with open(os.path.join(SCHEMAS_DIR, "dialogue_schema.json"), "r", encoding="utf-8") as f:
        dialogue = json.load(f)
    with open(os.path.join(SCHEMAS_DIR, "judgment_schema.json"), "r", encoding="utf-8") as f:
        judgment = json.load(f)
    return {"oracle": oracle, "dialogue": dialogue, "judgment": judgment}


def _load_contexts():
    """加载验证用玩家处境"""
    with open(os.path.join(FIXTURES_DIR, "player_contexts.json"), "r", encoding="utf-8") as f:
        return json.load(f)


def _build_oracle_message(context: dict) -> str:
    """组装天命面具的 user message"""
    return f"""【当前面具：天命】

现在是第 {context['day_number']} 天的早晨。
玩家状态：
- 天的善意值 benevolence = {context['benevolence']}
- 天的投入度 engagement = {context['engagement']}
- 玩家对真相的理解 depth = {context['truth_proximity']}

请抽取一张塔罗牌，生成今日预言。以 JSON 格式返回（见 oracle_schema）。"""


def _build_dialogue_message(context: dict) -> str:
    """组装化身面具的 user message"""
    return f"""【当前面具：化身 —— 正在扮演 Padwin】

现在是第 {context['day_number']} 天的 afternoon。
Padwin 对玩家的好感度当前为 {context['npc_affection']['padwin']}。

玩家走向 Padwin，说了一句：「Padwin，我有件事想问你……关于这片森林。」

请以 Padwin 的身份回应玩家。
以 JSON 格式返回（见 dialogue_schema）。"""


def _build_judgment_message(context: dict) -> str:
    """组装审判面具的 user message"""
    return f"""【当前面具：审判 —— 午夜结算】

现在是第 {context['day_number']} 天的 midnight。
玩家状态：
- benevolence = {context['benevolence']}
- engagement = {context['engagement']}
- truth_proximity = {context['truth_proximity']}

请生成今日午夜回顾叙事。
以 JSON 格式返回（见 judgment_schema）。"""


def run_v1(provider: str = DEFAULT_PROVIDER, model: str = DEFAULT_MODEL) -> dict:
    """
    运行 V1 验证：JSON 结构化输出可靠性。

    Returns:
        验证结果字典
    """
    print("─" * 60)
    print("  V1: JSON 结构化输出可靠性验证")
    print("  三种面具 × 30 次调用 = 90 次")
    print("─" * 60)

    system_prompt = _load_prompts()
    schemas = _load_schemas()
    contexts = _load_contexts()

    masks = [
        ("天命 (Oracle)", _build_oracle_message, schemas["oracle"]),
        ("化身 (Dialogue)", _build_dialogue_message, schemas["dialogue"]),
        ("审判 (Judgment)", _build_judgment_message, schemas["judgment"]),
    ]

    report = VerificationReport(name="v1_json_reliability")

    total_calls = 0
    total_success = 0
    total_time = 0.0

    for mask_name, msg_builder, schema in masks:
        print(f"\n  ▸ {mask_name}")
        success_count = 0
        recovery_counts = {"direct": 0, "regex_code_block": 0, "regex_braces": 0, "failed": 0}
        times = []

        for i in range(V1_ITERATIONS):
            ctx = contexts[i % len(contexts)]
            user_msg = msg_builder(ctx)

            t0 = time.time()
            parsed, raw_text, first_try, _ = call_llm_structured(
                system_prompt=system_prompt,
                user_message=user_msg,
                json_schema=schema,
                provider=provider,
                model=model,
            )
            elapsed = time.time() - t0
            times.append(elapsed)

            # 用完整解析器再试一次（如果 first_try 失败）
            if parsed is not None:
                success_count += 1
                recovery_counts["direct"] += 1
            else:
                # 用三层恢复再尝试
                result = parse_json_response(raw_text, expected_schema=schema)
                if result.success:
                    success_count += 1
                    recovery_counts[result.recovery_method] += 1
                else:
                    recovery_counts["failed"] += 1

            total_calls += 1
            total_time += elapsed

            if (i + 1) % 10 == 0:
                print(f"     {i+1}/{V1_ITERATIONS} 次完成 (当前成功率: {success_count}/{i+1})")

        rate = success_count / V1_ITERATIONS * 100
        avg_time = sum(times) / len(times)
        print(f"     成功率: {rate:.1f}% | 平均延迟: {avg_time:.1f}s")
        print(f"     恢复方法: 直接={recovery_counts['direct']} "
              f"代码块={recovery_counts['regex_code_block']} "
              f"正则提取={recovery_counts['regex_braces']} "
              f"失败={recovery_counts['failed']}")

        report.summary[mask_name] = {
            "success_rate": round(rate, 1),
            "avg_latency_s": round(avg_time, 1),
            "recovery_counts": recovery_counts,
        }

        total_success += success_count

    overall_rate = total_success / total_calls * 100
    passed = overall_rate >= 95.0

    report.summary["overall_success_rate"] = round(overall_rate, 1)
    report.summary["total_calls"] = total_calls
    report.passed = passed

    print(f"\n  ── V1 总体结果 ──")
    print(f"  总调用: {total_calls} | 总成功: {total_success} | 总成功率: {overall_rate:.1f}%")
    print(f"  通过标准: >= 95% | 判定: {'[PASS]' if passed else '[FAIL]'}")

    # 保存报告
    output_dir = os.path.join(RESULTS_DIR, datetime.now().strftime("%Y%m%d_%H%M%S"))
    from utils.scorer import save_report
    save_report(report, output_dir)
    print(f"  报告已保存: {output_dir}")

    return {"name": "v1", "passed": passed, "success_rate": overall_rate, "report": report}
