"""
ai_verify ——「天」Agent AI 离线验证主入口

用法：
    python run_all.py                    # 一键运行第一批全部验证
    python run_all.py --v1               # 只运行 V1
    python run_all.py --v2               # 只运行 V2
    python run_all.py --v3               # 只运行 V3
    python run_all.py --batch 2          # 运行第二批验证
    python run_all.py --chat padwin      # 交互式对话
    python run_all.py --list-npcs        # 列出可用 NPC
"""

import sys
import os

# 确保项目根目录在 path 中
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import RESULTS_DIR, PROMPTS_DIR


def main():
    import argparse
    parser = argparse.ArgumentParser(description="「天」Agent AI 离线验证工具")
    parser.add_argument("--v1", action="store_true", help="仅运行 V1: JSON 结构化输出可靠性")
    parser.add_argument("--v2", action="store_true", help="仅运行 V2: NPC 角色扮演稳定性")
    parser.add_argument("--v3", action="store_true", help="仅运行 V3: 塔罗解读文学质量")
    parser.add_argument("--all", action="store_true", default=True, help="运行所有第一批验证（默认）")
    parser.add_argument("--batch", type=int, choices=[1, 2], default=1,
                        help="运行第几批验证（1=核心验证, 2=深度验证）")
    parser.add_argument("--chat", type=str, metavar="NPC",
                        help="交互式对话模式（如: --chat padwin）")
    parser.add_argument("--list-npcs", action="store_true", help="列出可用的 NPC 角色卡")
    args = parser.parse_args()

    # ── 特殊命令：列出 NPC ──
    if args.list_npcs:
        _list_npcs()
        return

    # ── 特殊命令：交互式对话 ──
    if args.chat:
        _launch_chat(args.chat)
        return

    # ── 批量验证 ──
    _run_verification(args)


def _list_npcs():
    """列出 prompts/ 下所有 NPC 角色卡"""
    print("=" * 40)
    print("  可用 NPC 角色卡")
    print("=" * 40)
    for f in sorted(os.listdir(PROMPTS_DIR)):
        if f.startswith("npc_") and f.endswith(".txt"):
            npc_id = f[4:-4]  # 去掉 npc_ 前缀和 .txt 后缀
            path = os.path.join(PROMPTS_DIR, f)
            # 读第一行获取基本信息
            with open(path, "r", encoding="utf-8") as fh:
                first_line = fh.readline().strip().lstrip("#").strip()
            print(f"  {npc_id:15s} — {first_line}")
    print()
    print("  用法: python run_all.py --chat <npc_id>")


def _launch_chat(npc_id: str):
    """启动交互式对话"""
    from interactive_chat import run_chat
    try:
        run_chat(npc_id)
    except FileNotFoundError as e:
        print(f"[ERROR] {e}")
        print("  可用 NPC：")
        _list_npcs()
        sys.exit(1)


def _run_verification(args):
    from verifiers.json_reliability import run_v1
    from verifiers.npc_consistency import run_v2
    from verifiers.tarot_quality import run_v3

    # 检查 API key
    from config import ANTHROPIC_API_KEY, OPENAI_API_KEY, SILICONFLOW_API_KEY
    if not ANTHROPIC_API_KEY and not OPENAI_API_KEY and not SILICONFLOW_API_KEY:
        print("[ERROR] 未检测到任何 API Key，请检查 .env 文件")
        print("  SILICONFLOW_API_KEY=sk-...")
        print("  OPENAI_API_KEY=sk-...")
        print("  ANTHROPIC_API_KEY=sk-ant-...")
        sys.exit(1)

    print("=" * 60)
    print("  「天」Agent AI 离线验证工具")
    print("  成为艾莉森的一天 -- AI 叙事质量验证")
    print("=" * 60)

    if SILICONFLOW_API_KEY:
        print(f"  [OK] 检测到 SILICONFLOW_API_KEY (硅基流动)")
    if ANTHROPIC_API_KEY:
        print(f"  [OK] 检测到 ANTHROPIC_API_KEY (Claude API)")
    if OPENAI_API_KEY:
        print(f"  [OK] 检测到 OPENAI_API_KEY (OpenAI API)")
    print()

    results = {}

    if args.batch == 1:
        run_specific = args.v1 or args.v2 or args.v3
        should_run_v1 = not run_specific or args.v1
        should_run_v2 = not run_specific or args.v2
        should_run_v3 = not run_specific or args.v3

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
            passed = result.get("passed", False)
            if passed is None:
                status = "[待人工评分]"
            elif passed:
                status = "[PASS]"
            else:
                status = "[FAIL]"
                all_passed = False
            print(f"  {name.upper()}: {status}")

        if all_passed:
            print()
            print("  [OK] 全部通过！可以进入 Game 侧 AI 接入阶段。")
        else:
            print()
            print("  [WARN] 部分验证未通过或待评分。建议：")
            print("     1. 查看 results/ 目录下的详细报告")
            print("     2. 分析失败样本的 raw_output")
            print("     3. 调整 prompts/ 下的 Prompt 资产")
            print("     4. 重新运行验证")

    elif args.batch == 2:
        print("  第二批验证（深度验证）-- 待实现")
        print("  V4: 午夜结算叙事")
        print("  V5: 裂缝独白质量")
        print("  V6: 跨天记忆一致性")

    print()
    print(f"  详细报告: {RESULTS_DIR}/")


if __name__ == "__main__":
    main()
