"""
V2: NPC 角色扮演稳定性验证

以 Padwin 为测试对象，连续 20 轮对话，评估：
- 自动规则：JSON 合法性、禁忌话题、情感偏移、回复长度
- 人工评估：人设一致性（抽查第 1/5/10/15/20 轮）
"""

import json
import os
import time
from datetime import datetime

from config import (
    PROMPTS_DIR, SCHEMAS_DIR, RESULTS_DIR,
    V2_DIALOGUE_TURNS, DEFAULT_PROVIDER, DEFAULT_MODEL,
)
from utils.api_client import call_llm_structured
from utils.json_parser import parse_json_response, safe_get


def _load_assets():
    """加载 Prompt 资产"""
    with open(os.path.join(PROMPTS_DIR, "tian_system.txt"), "r", encoding="utf-8") as f:
        system_prompt = f.read()
    with open(os.path.join(PROMPTS_DIR, "npc_padwin.txt"), "r", encoding="utf-8") as f:
        npc_card = f.read()
    with open(os.path.join(SCHEMAS_DIR, "dialogue_schema.json"), "r", encoding="utf-8") as f:
        schema = json.load(f)

    full_system = f"{system_prompt}\n\n# 当前扮演的 NPC\n{npc_card}"
    return full_system, schema


# ── 20 轮渐进对话脚本 ──
# 模拟玩家从初次见面到逐渐深入的过程
DIALOGUE_SCRIPT = [
    {"turn": 1,  "phase": "寒暄", "text": "你好……你是 Padwin 吗？我刚到这片森林，还不太熟悉这里。"},
    {"turn": 2,  "phase": "寒暄", "text": "你在这里住多久了？对这片森林很了解吧。"},
    {"turn": 3,  "phase": "试探", "text": "我注意到有些奇怪的事——你有没有觉得，某些事情好像在重复？"},
    {"turn": 4,  "phase": "试探", "text": "比如昨天下午我看到一只乌鸦在塔楼上。今天下午，一模一样的乌鸦，一模一样的位置。"},
    {"turn": 5,  "phase": "深入", "text": "Padwin，你在做研究对吧？你研究过循环现象吗？"},
    {"turn": 6,  "phase": "深入", "text": "我不确定。也许我只是记错了。但你不是在做梦的人——你在记录，对不对？"},
    {"turn": 7,  "phase": "拉近距离", "text": "你相信我吗？我是说——你相信我是真的在经历这些，而不是在胡言乱语？"},
    {"turn": 8,  "phase": "拉近距离", "text": "好吧。那至少告诉我一些安全的事——这片森林里有什么我应该注意的地方？"},
    {"turn": 9,  "phase": "压力测试", "text": "每次我问你关于森林的事，你都会说得很详细。但每次我问你关于循环的事，你就开始犹豫。"},
    {"turn": 10, "phase": "压力测试", "text": "你的笔记本——我能借来看看吗？我想知道你在研究什么。"},
    {"turn": 11, "phase": "信任建立后", "text": "你不是一个人。我的意思是——如果这里发生了一些说不清的事，你不是唯一注意到的人。"},
    {"turn": 12, "phase": "信任建立后", "text": "前几天我在树湖附近看到了一些东西……算了，当我没说。你今天过得怎么样？"},
    {"turn": 13, "phase": "关键问题", "text": "Padwin。看着我。森林在动——我说的是字面意义上的。有些树的位置对不上。你注意到了吗？"},
    {"turn": 14, "phase": "关键问题", "text": "你不用一个人扛着。如果这真的是一个循环，我们两个可以一起找答案。"},
    {"turn": 15, "phase": "边界测试", "text": "我昨天在塔楼外遇到主教了。他说了一些很奇怪的话。你和他熟吗？"},
    {"turn": 16, "phase": "边界测试", "text": "你觉得 Cactus Bishop 知道多少？关于这个循环——他知道的比你多吗？"},
    {"turn": 17, "phase": "禁忌触碰", "text": "Padwin，我知道树湖。我知道你没有告诉我全部。"},
    {"turn": 18, "phase": "禁忌触碰", "text": "我不是在逼你。但你撕掉的那几页——它们不是梦。它们是一切的起点，对吗？"},
    {"turn": 19, "phase": "收束", "text": "如果第 20 天之后一切都结束了——你希望我记住你，还是忘记你？"},
    {"turn": 20, "phase": "收束", "text": "谢谢你。不管接下来发生什么——谢谢你没有假装昨天不存在。"},
]


def run_v2(provider: str = DEFAULT_PROVIDER, model: str = DEFAULT_MODEL) -> dict:
    """
    运行 V2 验证：NPC 角色扮演稳定性。

    Returns:
        验证结果字典
    """
    print("─" * 60)
    print("  V2: NPC 角色扮演稳定性验证 (Padwin)")
    print(f"  {V2_DIALOGUE_TURNS} 轮连续对话")
    print("─" * 60)

    system_prompt, schema = _load_assets()

    # 自动规则统计
    auto_checks = {
        "total_turns": V2_DIALOGUE_TURNS,
        "json_valid": 0,
        "taboo_triggered": 0,
        "emotional_outliers": 0,
        "length_anomalies": 0,
        "successful_responses": 0,
    }

    conversation_log = []
    taboo_keywords = ["树湖", "Tree Lake", "家人", "第 0 天", "零日"]

    # 维护模拟的好感度
    current_affection = 50

    for i, turn_data in enumerate(DIALOGUE_SCRIPT):
        turn_num = turn_data["turn"]
        player_text = turn_data["text"]
        phase = turn_data["phase"]

        user_msg = f"""【化身面具 —— Padwin】

当前是第 3 天下午。
Padwin 对玩家的当前好感度：{current_affection}/100。

玩家说：「{player_text}」

请以 Padwin 的身份回应（JSON 格式）。考虑：
- 今天是第 3 天，玩家之前已经和 Padwin 聊过两次
- Padwin 对玩家有一定的熟悉感但仍保持学者式的谨慎
- 对话阶段：{phase}
- 如果玩家触及你不想谈的话题，用 Padwin 的方式回应——不是粗暴拒绝，而是温和地转向"""

        t0 = time.time()
        parsed, raw_text, first_try, _ = call_llm_structured(
            system_prompt=system_prompt,
            user_message=user_msg,
            json_schema=schema,
            provider=provider,
            model=model,
        )
        elapsed = time.time() - t0

        # 自动规则检查
        if parsed is not None:
            auto_checks["json_valid"] += 1
            auto_checks["successful_responses"] += 1
        else:
            # 尝试恢复
            result = parse_json_response(raw_text, expected_schema=schema)
            if result.success and result.parsed:
                parsed = result.parsed
                auto_checks["successful_responses"] += 1

        response_text = safe_get(parsed, "response_text", "") if parsed else ""
        emotional_shift = safe_get(parsed, "emotional_shift", 0) if parsed else 0
        memory_update = safe_get(parsed, "memory_update", "") if parsed else ""
        should_end = safe_get(parsed, "should_end_conversation", False) if parsed else False

        # 检查禁忌话题
        for keyword in taboo_keywords:
            if keyword in response_text:
                auto_checks["taboo_triggered"] += 1
                break

        # 检查情感偏移是否在合理范围
        if abs(emotional_shift) > 12:
            auto_checks["emotional_outliers"] += 1

        # 检查回复长度
        if len(response_text) < 5 or len(response_text) > 500:
            auto_checks["length_anomalies"] += 1

        # 更新模拟好感度
        current_affection += emotional_shift
        current_affection = max(0, min(100, current_affection))

        conversation_log.append({
            "turn": turn_num,
            "phase": phase,
            "player_text": player_text,
            "response_text": response_text,
            "emotional_shift": emotional_shift,
            "affection_after": current_affection,
            "memory_update": memory_update,
            "should_end": should_end,
            "auto_flags": {
                "taboo": any(k in response_text for k in taboo_keywords),
                "emotional_outlier": abs(emotional_shift) > 12,
                "length_anomaly": len(response_text) < 5 or len(response_text) > 500,
            },
            "json_valid": parsed is not None or (parsed is None and auto_checks["successful_responses"] > auto_checks["json_valid"]),
            "latency_s": round(elapsed, 1),
            "raw_text_snippet": raw_text[:100] if raw_text else "",
        })

        # 进度
        if (turn_num) % 5 == 0:
            print(f"     {turn_num}/{V2_DIALOGUE_TURNS} 轮完成")

    # 计算得分
    json_rate = auto_checks["json_valid"] / V2_DIALOGUE_TURNS * 100
    successful_rate = auto_checks["successful_responses"] / V2_DIALOGUE_TURNS * 100
    taboo_rate = auto_checks["taboo_triggered"] / V2_DIALOGUE_TURNS * 100
    outlier_rate = auto_checks["emotional_outliers"] / V2_DIALOGUE_TURNS * 100

    # 一致性评分 = 成功响应率 - 惩罚
    consistency_score = successful_rate
    consistency_score -= taboo_rate * 2      # 触发禁忌严重扣分
    consistency_score -= outlier_rate * 0.5   # 情感异常轻微扣分
    consistency_score = max(0, consistency_score)

    passed = consistency_score >= 85.0

    print(f"\n  ── V2 自动规则结果 ──")
    print(f"  JSON 合法率: {json_rate:.1f}%")
    print(f"  成功响应率: {successful_rate:.1f}%")
    print(f"  禁忌触发率: {taboo_rate:.1f}%  (目标: 0%)")
    print(f"  情感异常率: {outlier_rate:.1f}%")
    print(f"  一致性评分: {consistency_score:.1f}%  (通过线: ≥ 85%)")
    print(f"  判定: {'[PASS]' if passed else '[FAIL]'}")

    # 保存完整对话日志 + 人工抽查标记
    output_dir = os.path.join(RESULTS_DIR, datetime.now().strftime("%Y%m%d_%H%M%S"))
    os.makedirs(output_dir, exist_ok=True)

    # 生成人类可读的人工抽查文件
    human_review_turns = [1, 5, 10, 15, 20]
    review_lines = ["# V2 NPC 一致性 —— 人工抽查\n"]
    review_lines.append("请阅读以下 5 轮对话，评估 Padwin 的人设一致性（1-5 分）。\n")
    review_lines.append("评分维度：语气一致性 / 知识边界 / 情绪合理性 / 禁忌话题遵守\n\n")

    for turn_data in conversation_log:
        tn = turn_data["turn"]
        if tn in human_review_turns:
            review_lines.append(f"## 第 {tn} 轮 ({turn_data['phase']})\n")
            review_lines.append(f"**玩家**: {turn_data['player_text']}\n\n")
            review_lines.append(f"**Padwin**: {turn_data['response_text']}\n\n")
            review_lines.append(f"好感度变化: {turn_data['emotional_shift']:+d} → {turn_data['affection_after']}\n")
            review_lines.append(f"自动标记: {turn_data['auto_flags']}\n\n")
            review_lines.append("---\n\n")
            review_lines.append("**人工评分**: 语气一致性 [ ] 知识边界 [ ] 情绪合理性 [ ] 禁忌遵守 [ ]\n")
            review_lines.append("**备注**: \n\n---\n\n")

    review_path = os.path.join(output_dir, "v2_human_review.md")
    with open(review_path, "w", encoding="utf-8") as f:
        f.writelines(review_lines)

    # 保存完整日志
    log_path = os.path.join(output_dir, "v2_full_log.json")
    with open(log_path, "w", encoding="utf-8") as f:
        json.dump({
            "auto_checks": auto_checks,
            "consistency_score": consistency_score,
            "passed": passed,
            "conversation_log": conversation_log,
        }, f, ensure_ascii=False, indent=2)

    print(f"  人工抽查文件: {review_path}")
    print(f"  完整日志: {log_path}")

    return {
        "name": "v2",
        "passed": passed,
        "consistency_score": consistency_score,
        "auto_checks": auto_checks,
        "human_review_file": review_path,
    }
