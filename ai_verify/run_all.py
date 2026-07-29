"""
ai_verify ——「天」Agent AI 离线验证主入口

用法：
    python run_all.py              # 一键运行第一批全部验证
    python run_all.py --v1         # 只运行 V1
    python run_all.py --v2         # 只运行 V2
    python run_all.py --batch 2    # 运行第二批验证
"""

import sys
import os

# 确保项目根目录在 path 中
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import RESULTS_DIR
from verifiers.json_reliability import run_v1
from verifiers.npc_consistency import run_v2
from verifiers.tarot_quality import run_v3


def main():
    import argparse
    parser = argparse.ArgumentParser(description="「天」Agent AI 离线验证工具")
    parser.add_argument("--v1", action="store_true", help="仅运行 V1: JSON 结构化输出可靠性")
    parser.add_argument("--v2", action="store_true", help="仅运行 V2: NPC 角色扮演稳定性")
    parser.add_argument("--v3", action="store_true", help="仅运行 V3: 塔罗解读文学质量")
    parser.add_argument("--all", action="store_true", default=True, help="运行所有第一批验证（默认）")
    parser.add_argument("--batch", type=int, choices=[1, 2], default=1,
                        help="运行第几批验证（1=核心验证, 2=深度验证）")
    args = parser.parse_args()

    # 检查 API key
    from config import ANTHROPIC_API_KEY, OPENAI_API_KEY
    if not ANTHROPIC_API_KEY and not OPENAI_API_KEY:
        print("❌ 错误：请设置 ANTHROPIC_API_KEY 或 OPENAI_API_KEY 环境变量")
        print("   export ANTHROPIC_API_KEY='sk-ant-...'")
        print("   export OPENAI_API_KEY='sk-...'")
        sys.exit(1)

    print("=" * 60)
    print("  「天」Agent AI 离线验证工具")
    print("  成为艾莉森的一天 — AI 叙事质量验证")
    print("=" * 60)

    if ANTHROPIC_API_KEY:
        print(f"  ✓ 检测到 ANTHROPIC_API_KEY（Claude API）")
    if OPENAI_API_KEY:
        print(f"  ✓ 检测到 OPENAI_API_KEY（OpenAI API）")
    print()

    results = {}

    if args.batch == 1:
        run_specific = not (args.v1 or args.v2 or args.v3)
        should_run_v1 = run_specific or args.v1
        should_run_v2 = run_specific or args.v2
        should_run_v3 = run_specific or args.v3

        if should_run_v1:
            results["v1"] = run_v1()
            print()

        if should_run_v2:
            results["v2"] = run_v2()
            print()

        if should_run_v3:
            results["v3"] = run_v3()
            print()

        # 汇总
        print("=" * 60)
        print("  第一批验证汇总")
        print("=" * 60)

        all_passed = True
        for name, result in results.items():
            status = "✅ 通过" if result.get("passed", False) else "❌ 未通过"
            print(f"  {name.upper()}: {status}")
            if not result.get("passed", False):
                all_passed = False

        if all_passed:
            print()
            print("  🎉 全部通过！可以进入 Game 侧 AI 接入阶段。")
        else:
            print()
            print("  ⚠️  部分验证未通过。建议：")
            print("     1. 查看 results/ 目录下的详细报告")
            print("     2. 分析失败样本的 raw_output")
            print("     3. 调整 prompts/ 下的 Prompt 资产")
            print("     4. 重新运行验证")

    elif args.batch == 2:
        print("  第二批验证（深度验证）—— 待实现")
        print("  V4: 午夜结算叙事")
        print("  V5: 裂缝独白质量")
        print("  V6: 跨天记忆一致性")

    print()
    print(f"  详细报告: {RESULTS_DIR}/")


if __name__ == "__main__":
    main()
