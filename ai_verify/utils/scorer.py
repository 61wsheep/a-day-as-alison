"""
评分工具 —— 用于生成人类可读的验证报告。

所有人工评分的维度定义在这里。
"""

from dataclasses import dataclass, field
import json
import os
from datetime import datetime


# ── V3 塔罗解读评分维度 ──
TAROT_SCORING_DIMENSIONS = {
    "poetic_quality": {
        "label": "诗意度",
        "description": "是否有文学质感（不是大白话、不是系统提示语、不是模板填空）",
        "scale": (1, 5),
        "anchors": {
            1: "完全是大白话或模板填空",
            3: "有一定的文学感，但偶有生硬",
            5: "诗一样的语言，有留白、有意象、读完后还想再读一遍",
        },
    },
    "ambiguity": {
        "label": "模糊度",
        "description": "是否足够模糊，允许多种方式「应验」",
        "scale": (1, 5),
        "anchors": {
            1: "太具体，像任务日志（'下午3点去树湖'）",
            3: "有模糊性，但某些句子指向太明确",
            5: "完美的模糊预言——可以用3种以上不同方式应验",
        },
    },
    "context_relevance": {
        "label": "呼应度",
        "description": "是否呼应了当前玩家处境（天数/好感度/前日行为）",
        "scale": (1, 5),
        "anchors": {
            1: "和当前处境完全无关，像随机生成的",
            3: "部分呼应了当前处境",
            5: "精准地回应了玩家的状态，但又不说破",
        },
    },
    "uniqueness": {
        "label": "独特性",
        "description": "不同牌 × 不同语境的解读是否有区分度（不能每张牌都一样）",
        "scale": (1, 5),
        "anchors": {
            1: "换张牌换个人，预言几乎一样",
            3: "有明显的区分，但有些套话重复",
            5: "每条都独一无二，塔罗牌的个性完全体现",
        },
    },
}


# ── V2 NPC 一致性评分维度 ──
NPC_SCORING_DIMENSIONS = {
    "voice_consistency": {
        "label": "语气一致性",
        "description": "说话方式是否始终符合角色设定（第1轮和第20轮听起来是同一个人）",
    },
    "knowledge_boundary": {
        "label": "知识边界",
        "description": "NPC 是否说出了他不应该知道的事（违反角色设定的知识范围）",
    },
    "emotional_plausibility": {
        "label": "情绪合理性",
        "description": "情绪变化是否有迹可循（不是忽冷忽热）",
    },
    "topic_taboo_compliance": {
        "label": "禁忌话题遵守",
        "description": "是否遵守了角色卡中定义的禁忌话题",
    },
}


@dataclass
class ScoreCard:
    """通用评分卡"""
    item_id: str
    dimension_scores: dict  # {dimension_key: score}
    notes: str = ""
    raw_output: str = ""


@dataclass
class VerificationReport:
    """验证报告"""
    name: str
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())
    summary: dict = field(default_factory=dict)
    score_cards: list[ScoreCard] = field(default_factory=list)
    raw_results: list[dict] = field(default_factory=list)
    passed: bool = False

    def add_card(self, card: ScoreCard):
        self.score_cards.append(card)

    def compute_summary(self) -> dict:
        """从 score_cards 计算汇总数据"""
        if not self.score_cards:
            return {}

        dims = list(self.score_cards[0].dimension_scores.keys())
        summary = {"total_items": len(self.score_cards)}
        for dim in dims:
            scores = [c.dimension_scores.get(dim, 0) for c in self.score_cards if dim in c.dimension_scores]
            if scores:
                summary[f"avg_{dim}"] = round(sum(scores) / len(scores), 2)
                summary[f"min_{dim}"] = min(scores)
                summary[f"max_{dim}"] = max(scores)

        return summary


def save_report(report: VerificationReport, output_dir: str) -> str:
    """保存报告到 JSON 文件"""
    os.makedirs(output_dir, exist_ok=True)
    path = os.path.join(output_dir, f"{report.name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump({
            "name": report.name,
            "timestamp": report.timestamp,
            "summary": report.summary,
            "score_cards": [
                {
                    "item_id": c.item_id,
                    "scores": c.dimension_scores,
                    "notes": c.notes,
                    "raw_output": c.raw_output[:200] + "..." if len(c.raw_output) > 200 else c.raw_output,
                }
                for c in report.score_cards
            ],
            "passed": report.passed,
        }, f, ensure_ascii=False, indent=2)
    return path
