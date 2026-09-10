#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Dialogue Lab —— 《成为艾莉森的一天》AI 对话探针（离游戏，独立 Python 工程）

目的：不改游戏工程，就能
  1) 量化一次回复的 20s+ 到底花在哪（TTFT？全文？prefill？）
  2) 测同一句玩家话在不同配置下的 延迟 / token / 回复差异
  3) 验证 SiliconFlow/DeepSeek 是否给"稳定前缀"做缓存（= 引擎上下文分层值多少）
  4) 调 prompt 措辞，直观看语气/OOC

用法：
  python dialogue_lab.py --dry                 # 只拼装+估算 token，不发网络（验拼装）
  python dialogue_lab.py                       # 默认矩阵：baseline / stream / cachetest
  python dialogue_lab.py --configs baseline    # 只跑某一配置
  python dialogue_lab.py --max-tokens 256      # 覆盖限幅

key 解析顺序：环境变量 SILICONFLOW_API_KEY → --key → Godot user:// appdata 文件
纯标准库，无第三方依赖。只读游戏卡文件，不改游戏工程。
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime

# 让 Windows 终端能打印中文
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# ---------------------------------------------------------------------------
# 常量 —— 与引擎 ai_bridge.gd / ai_dialogue_session.gd 对齐
# ---------------------------------------------------------------------------
DEFAULT_GAME_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                 os.pardir, "成为艾莉森的一天")
BASE_URL = "https://api.siliconflow.cn/v1/chat/completions"
MODEL_DEFAULT = "deepseek-ai/DeepSeek-V3"
TEMPERATURE = 0.8
MAX_TOKENS_GLOBAL = 1024          # ai_bridge.MAX_TOKENS
MAX_TOKENS_DIALOGUE = 512         # AIDialogueSession.DIALOGUE_MAX_TOKENS
DIALOGUE_HARD_TIMEOUT = 30.0      # request_llm_with_guard
MEMORY_WINDOW = 5                 # 引擎保留最近 N 轮历史
MEMORY_TAIL = 5                   # 跨天记忆取末尾 N 条

# 线索显示名（对齐 game_manager.gd CLUE_NAMES）
CLUE_NAMES = {
    "clue_padwin_no_memory": "帕德温没有前世的记忆",
    "clue_cactus_scar": "主教颈上的勒痕",
    "clue_burn_scar": "自己背上的烧伤疤痕",
    "clue_soraya_repeat": "索拉雅机械重复的迎接",
    "clue_forest_fake": "塔楼中的森林起源之书",
    "clue_id_card": "树屋里与自己完全相符的身份证",
}


# ---------------------------------------------------------------------------
# key 解析
# ---------------------------------------------------------------------------
def resolve_key(cli_key: str = "") -> str:
    if cli_key:
        return cli_key.strip()
    env = os.environ.get("SILICONFLOW_API_KEY", "").strip()
    if env:
        return env
    # Godot 运行时写出的 user://ai_api_key.txt（Windows）
    appdata = os.environ.get("APPDATA", "")
    if appdata:
        cand = os.path.join(appdata, "Godot", "app_userdata",
                            "成为艾莉森的一天", "ai_api_key.txt")
        if os.path.exists(cand):
            k = open(cand, encoding="utf-8-sig").read().strip()
            if k:
                return k
    return ""


# ---------------------------------------------------------------------------
# 文件读取
# ---------------------------------------------------------------------------
def read_text(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read().strip()


# ---------------------------------------------------------------------------
# 上下文拼装 —— 逐行复刻引擎 ai_dialogue_session.gd::_build_payload / _heaven_injection
# state 字段见下方 build_payload() 的注释；返回 (system, user) 纯文本，
# 与引擎发出去的字符串逐字符一致，这样 A/B 才有意义。
# ---------------------------------------------------------------------------
def build_payload(state: dict) -> dict:
    game_root = state.get("game_root", DEFAULT_GAME_ROOT)
    ai_dir = os.path.join(game_root, "ai")
    npc_id = state["npc_id"]

    system_text = read_text(os.path.join(ai_dir, "tian_system.txt"))
    card_text = read_text(os.path.join(ai_dir, "npc_%s.txt" % npc_id))
    schema_text = read_text(os.path.join(ai_dir, "dialogue_schema.json"))

    day = int(state.get("day", 1))
    time_id = state.get("time_id", "morning")
    affection = int(state.get("affection", 50))
    today_reading = state.get("daily_tarot_card", "")
    known_clues = list(state.get("clues_found", []))
    memory_updates = list(state.get("memory_updates", []))
    history = list(state.get("history", []))          # [{player, npc}]
    player_input = str(state.get("player_input", ""))
    turn = int(state.get("turn", 1))
    is_opening = bool(state.get("is_opening", False))

    # ---- 门控挡刀：玩家已知线索注入 ----
    clue_names = [CLUE_NAMES.get(c, c) for c in known_clues]

    # ---- 跨天记忆 ----
    if memory_updates:
        tail = memory_updates[-MEMORY_TAIL:]
        cross_day = "\n".join("- %s" % m for m in tail)
    else:
        cross_day = "（尚无跨天记忆 —— 今天是你们第一次见面）"

    # ---- 本轮历史 ----
    if history:
        recent = history[-MEMORY_WINDOW:]
        lines = []
        for h in recent:
            lines.append("玩家: %s\n%s: %s" % (h.get("player", ""), npc_id, h.get("npc", "")))
        history_block = "\n".join(lines)
    else:
        history_block = "（第一次对话）"

    # ---- user 消息（与引擎逐字一致）----
    user = ""
    if is_opening:
        user += "【化身面具 —— 正在扮演 %s】\n\n" % npc_id
        user += "第 %d 天。%s。%s 对玩家的好感度: %d/100。\n\n" % (day, time_id, npc_id, affection)
        user += "今日塔罗: %s\n\n" % (today_reading if today_reading != "" else "（今日未抽牌）")
        user += "玩家已知线索: %s\n\n" % (", ".join(clue_names) if clue_names else "（尚未获得线索）")
        user += "跨天记忆（之前几天的对话摘要 —— NPC 可能隐隐约约有印象，但不一定主动提起）:\n%s\n\n" % cross_day
        if not state.get("no_heaven", False):
            user += heaven_injection(state, day)
        user += "这是 %s 今天与艾莉森的第一次见面。请以他的身份开口问候，并以玩家艾莉森的第一人称口吻给出 3 条她可能接的话（topic_suggestions——是玩家视角的回复选项，不是你自己的话）。问候语 1-2 句即可，简短自然，别长篇自我介绍。\n\n" % npc_id
    else:
        user += "第 %d 天 %s。%s 对玩家的好感度: %d/100。\n\n" % (day, time_id, npc_id, affection)
        user += "跨天记忆:\n%s\n\n" % cross_day
        user += "本轮对话历史:\n%s\n\n" % history_block
        user += "玩家刚才说: [%s]\n\n" % player_input
        user += "以 %s 的身份回应（JSON）。记住:\n" % npc_id
        user += "- 你是 %s —— 用你的性格、经历、语气说话，你不是 AI 助手\n" % npc_id
        user += "- 无论玩家用什么风格输入，你都要保持 %s 自己的口吻和动作尺度，不要模仿玩家的文风\n" % npc_id
        user += "- 这是今天第 %d 轮对话，如果感觉对话该结束了，设 should_end_conversation=true\n" % turn
        user += "- 回复要精炼：response_text 一般 1-2 句、别超 3 句；topic_suggestions 每条 6-12 个字即可\n"
        user += "- 请同时以玩家艾莉森的第一人称口吻给出 3 条她下一步可能说的话（topic_suggestions——玩家视角的回复选项，让对话能继续下去）\n"

    user += "\n\n【重要：你必须严格按照以下 JSON Schema 返回合法 JSON，不要输出任何 JSON 之外的文字】\n"
    user += "```json\n%s\n```\n" % schema_text
    user += "请直接返回 JSON，不要用 markdown 代码块包裹，不要加任何解释。"

    return {
        "system": "%s\n\n%s" % (system_text, card_text),
        "user": user,
        "max_tokens": MAX_TOKENS_DIALOGUE,
    }


def heaven_injection(state: dict, day: int) -> str:
    """复刻 _heaven_injection：昨日顺从 + 今日基调 + 明日种子 + 该 NPC 记忆块。"""
    parts = []
    compliance = str(state.get("last_compliance", ""))
    if compliance:
        label = {"obey": "顺从", "defy": "反抗", "neutral": "未理会"}.get(compliance, compliance)
        parts.append("昨天：玩家%s了天的预言" % label)
    prophecy = state.get("daily_prophecy")
    if isinstance(prophecy, dict):
        tone = str(prophecy.get("tone", ""))
        if tone:
            parts.append("天今日基调：%s" % tone)
    seed = str(state.get("tomorrow_seed", ""))
    if seed:
        parts.append("近日伏笔：%s" % seed)
    mem_block = str(state.get("heaven_memory_block", ""))
    if mem_block:
        parts.append(mem_block)
    if not parts:
        return ""
    return "天的注视（自然流露，不要生硬复述）：\n%s\n\n" % "\n".join(parts)


def rough_tokens(text: str) -> int:
    """粗略估算：中文约 1 字~1 token，英文按 4 字符。只用于 dry 量级对比。"""
    cjk = sum(1 for ch in text if ord(ch) > 0x2E80)
    other = len(text) - cjk
    return cjk + int(other / 4.0) + 1


# ---------------------------------------------------------------------------
# HTTP —— 非流式与流式(SSE)都在这里；计时到毫秒
# ---------------------------------------------------------------------------
def _request_once(messages, model, max_tokens, temperature, api_key,
                  stream: bool, timeout: float):
    """返回 dict：ok, ttft_ms, total_ms, content, usage, http_code, error。
    content 在非流式 = 完整回复；流式 = 累积的回复。"""
    body = json.dumps({
        "model": model,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "stream": stream,
        "response_format": {"type": "json_object"},
        "messages": messages,
    }, ensure_ascii=False).encode("utf-8")

    req = urllib.request.Request(
        BASE_URL, data=body,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Authorization": "Bearer %s" % api_key,
        })

    t0 = time.monotonic()
    ttft_ms = None
    content = ""
    usage = {}
    http_code = None
    error = ""
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            http_code = resp.getcode()
            if not stream:
                raw = resp.read().decode("utf-8", "replace")
                total_ms = (time.monotonic() - t0) * 1000.0
                try:
                    env = json.loads(raw)
                    content = (env.get("choices") or [{}])[0].get("message", {}).get("content", "")
                    usage = env.get("usage", {}) or {}
                except Exception as e:
                    error = "解析响应失败: %s | %s" % (e, raw[:200])
                return _mk(True, ttft_ms, total_ms, content, usage, http_code, error)
            else:
                # 流式：逐行读 SSE
                for line in resp:
                    if not line:
                        continue
                    line = line.decode("utf-8", "replace").strip()
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if ttft_ms is None:
                        ttft_ms = (time.monotonic() - t0) * 1000.0
                    if data == "[DONE]":
                        break
                    try:
                        chunk = json.loads(data)
                    except Exception:
                        continue
                    if ttft_ms is None:
                        ttft_ms = (time.monotonic() - t0) * 1000.0
                    choices = chunk.get("choices") or []
                    if choices:
                        delta = (choices[0].get("delta") or {}).get("content", "")
                        if delta:
                            content += delta
                    if chunk.get("usage"):
                        usage = chunk["usage"]
                total_ms = (time.monotonic() - t0) * 1000.0
                if not content and not usage and not error:
                    error = "流式响应但未收到内容（http=%s）" % http_code
                return _mk(True, ttft_ms, total_ms, content, usage, http_code, error)
    except urllib.error.HTTPError as e:
        http_code = e.code
        try:
            detail = e.read().decode("utf-8", "replace")[:200]
        except Exception:
            detail = ""
        return _mk(False, None, (time.monotonic() - t0) * 1000.0, "", {}, http_code,
                   "HTTP %d %s" % (e.code, detail))
    except Exception as e:
        return _mk(False, None, (time.monotonic() - t0) * 1000.0, "", {}, http_code,
                   "%s: %s" % (type(e).__name__, e))


def _mk(ok, ttft, total, content, usage, code, error):
    return {"ok": ok, "ttft_ms": ttft, "total_ms": total, "content": content,
            "usage": usage, "http_code": code, "error": error}


# ---------------------------------------------------------------------------
# 跑一个 3 轮脚本，逐轮新建请求（= 引擎无状态逐轮模式）
# ---------------------------------------------------------------------------
def run_script(state: dict, script: list, config: dict, api_key: str) -> list:
    """script = [player_line1, player_line2, ...]，首轮为开场问候。
    返回每轮的 result 列表。"""
    results = []
    for i, player_line in enumerate(script):
        s = dict(state)
        s["is_opening"] = (i == 0)
        s["player_input"] = player_line if i > 0 else ""
        s["turn"] = i + 1
        payload = build_payload(s)
        messages = [
            {"role": "system", "content": payload["system"]},
            {"role": "user", "content": payload["user"]},
        ]
        r = _request_once(messages, config["model"], config["max_tokens"],
                          config["temperature"], api_key, config["stream"],
                          config.get("timeout", DIALOGUE_HARD_TIMEOUT))
        r["_turn"] = i + 1
        r["_player"] = player_line
        r["_prompt_chars"] = len(payload["system"]) + len(payload["user"])
        r["_sys_chars"] = len(payload["system"])
        r["_usr_chars"] = len(payload["user"])
        r["_est_tokens"] = rough_tokens(payload["system"]) + rough_tokens(payload["user"])
        results.append(r)
        if not r["ok"]:
            break   # 配置问题/超限就停，别空烧钱
    return results


# ---------------------------------------------------------------------------
# 报告
# ---------------------------------------------------------------------------
def fmt_ms(x):
    return "-" if x is None else "%.0f" % x


def fmt_sec(x):
    return "-" if x is None else "%.1fs" % (x / 1000.0)


def parse_reply(content: str) -> dict:
    """尽力从 content 解出 JSON（模型可能前后带杂字）。"""
    if not content:
        return {}
    try:
        return json.loads(content)
    except Exception:
        # 去 ```json 围栏
        s = content.strip()
        if s.startswith("```"):
            s = s.strip("`")
            if s.startswith("json"):
                s = s[4:]
        s = s.strip()
        # 从第一个 { 到最后一个 }
        a, b = s.find("{"), s.rfind("}")
        if a >= 0 and b > a:
            try:
                return json.loads(s[a:b + 1])
            except Exception:
                pass
        return {}


def summarize(config_name: str, results: list) -> dict:
    row = {"config": config_name, "turns": []}
    total = 0.0
    for r in results:
        total += r["total_ms"] if r["total_ms"] else 0
        usage = r.get("usage", {}) or {}
        row["turns"].append({
            "turn": r["_turn"],
            "player": r["_player"],
            "ok": r["ok"],
            "ttft_ms": r["ttft_ms"],
            "total_ms": r["total_ms"],
            "prompt_tokens": usage.get("prompt_tokens"),
            "cache_hit": usage.get("prompt_cache_hit_tokens"),
            "cache_miss": usage.get("prompt_cache_miss_tokens"),
            "completion_tokens": usage.get("completion_tokens"),
            "total_tokens": usage.get("total_tokens"),
            "prompt_chars": r["_prompt_chars"],
            "sys_chars": r["_sys_chars"],
            "usr_chars": r["_usr_chars"],
            "est_tokens": r["_est_tokens"],
            "error": r.get("error", ""),
            "reply": parse_reply(r.get("content", "")),
        })
    row["total_ms"] = total
    return row


def print_summary(summaries: list) -> None:
    print("\n==================== 汇总 ====================\n")
    for s in summaries:
        print("◆ %s   总耗时 %s" % (s["config"], fmt_sec(s["total_ms"])))
        for t in s["turns"]:
            print("  第%d轮 %s | %s(%s" % (
                t["turn"],
                "OK " if t["ok"] else "FAIL",
                "首字%s " % fmt_sec(t["ttft_ms"]) if t["ttft_ms"] is not None else "首字-  ",
                "全文%s)" % fmt_sec(t["total_ms"]) if t["total_ms"] is not None else "全文-)"))
            print("      prompt tok=%-5s 缓存hit=%-5s miss=%-5s 出=%-5s (字符 sys=%d+usr=%d, 估tok=%d)"
                  % (t["prompt_tokens"], t["cache_hit"], t["cache_miss"],
                     t["completion_tokens"], t["sys_chars"], t["usr_chars"], t["est_tokens"]))
            if t["error"]:
                print("      ERROR: %s" % t["error"][:160])
            reply = t["reply"]
            if reply:
                print("      %s → “%s”" % (t["player"], str(reply.get("response_text", ""))[:120]))
            else:
                print("      %s → （无/非JSON回复）" % t["player"])
            if not t["ok"]:
                break
    print("")


def save_runs(summaries: list, state: dict, script: list) -> str:
    os.makedirs("runs", exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = os.path.join("runs", "report_%s.json" % stamp)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"time": stamp, "state": state, "script": script,
                   "summaries": summaries}, f, ensure_ascii=False, indent=2)
    return path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def default_state() -> dict:
    # 对齐引擎 GameManager 初值：day1 / padwin 好感 50 / 无线索
    return {
        "game_root": DEFAULT_GAME_ROOT,
        "npc_id": "padwin",
        "day": 1,
        "time_id": "morning",
        "affection": 50,
        "daily_tarot_card": "",
        "clues_found": [],
        "memory_updates": [],
        "history": [],
        "last_compliance": "",
        "daily_prophecy": None,
        "tomorrow_seed": "",
        "heaven_memory_block": "",
        "no_heaven": False,
    }


DEFAULT_SCRIPT = [
    "（把带来的番茄递过去）这个给你，就当见面礼。",
    "你右眉那道疤……是怎么来的？",
]


def main():
    ap = argparse.ArgumentParser(description="《成为艾莉森的一天》AI 对话探针")
    ap.add_argument("--dry", action="store_true",
                    help="只拼装 + 估算 token，不发网络请求")
    ap.add_argument("--npc", default="padwin")
    ap.add_argument("--model", default=MODEL_DEFAULT)
    ap.add_argument("--max-tokens", type=int, default=MAX_TOKENS_DIALOGUE)
    ap.add_argument("--temperature", type=float, default=TEMPERATURE)
    ap.add_argument("--key", default="")
    ap.add_argument("--timeout", type=float, default=DIALOGUE_HARD_TIMEOUT)
    ap.add_argument("--configs", default="baseline,stream,cachetest",
                    help="逗号分隔：baseline(非流式)/stream(流式)/cachetest(同文连打两次测缓存)")
    ap.add_argument("--no-heaven", action="store_true", help="user 消息去掉天的注视层")
    args = ap.parse_args()

    state = default_state()
    state["npc_id"] = args.npc
    state["no_heaven"] = args.no_heaven
    script = DEFAULT_SCRIPT

    # ---- dry：只拼装首轮 + 二轮，给 token 量级 ----
    if args.dry:
        print("== DRY：只拼装，不发网络 ==\n")
        print("npc=%s  卡: ai/npc_%s.txt + tian_system.txt + dialogue_schema.json" % (args.npc, args.npc))
        for i in range(2):
            s = dict(state)
            s["is_opening"] = (i == 0)
            s["player_input"] = script[i] if i > 0 else ""
            s["turn"] = i + 1
            p = build_payload(s)
            est = rough_tokens(p["system"]) + rough_tokens(p["user"])
            print("\n---- %s ----" % ("开场问候(user 消息)" if i == 0 else "第2轮(玩家: %s)" % script[i]))
            print("system 字符 %d (~%d tok)：tian_system + npc卡" % (len(p["system"]), rough_tokens(p["system"])))
            print("user   字符 %d (~%d tok)" % (len(p["user"]), rough_tokens(p["user"])))
            print("合计   ~%d tok/请求" % est)
            print("── system 前 300 字 ──\n%s" % p["system"][:300])
            print("── user 前 500 字 ──\n%s" % p["user"][:500])
        print("\n(dry 结束。去掉 --dry 即真打网络，需可用 key)")
        return

    # ---- live ----
    api_key = resolve_key(args.key)
    if not api_key:
        print("没有找到可用 key。请设环境变量 SILICONFLOW_API_KEY 或 --key <你的key>。")
        sys.exit(2)

    chosen = [c.strip() for c in args.configs.split(",") if c.strip()]
    configs = {
        "baseline": {"stream": False},
        "stream": {"stream": True},
        "cachetest": {"stream": False},   # 同一文重复打两次：验证稳定前缀缓存
    }
    summaries = []
    state_for_report = {k: v for k, v in state.items() if k != "game_root"}

    print("模型 %s | max_tokens=%d | temp=%.1f | 玩家脚本 %d 行" %
          (args.model, args.max_tokens, args.temperature, len(script)))
    print("按顺序跑：开场 → %s → %s\n" % (script[0], script[1]))

    for name in chosen:
        if name not in configs:
            print("未知配置：%s（可选 %s）" % (name, ",".join(configs)))
            continue
        base = configs[name]
        cfg = dict(base, model=args.model, max_tokens=args.max_tokens,
                   temperature=args.temperature, timeout=args.timeout)
        print("───── 配置：%s（%s）─────" % (name, "流式" if cfg["stream"] else "非流式"))
        if name == "cachetest":
            # 同文连打两次：第 2 次应吃到稳定前缀缓存（如果供应商支持）
            for run_i in (1, 2):
                results = run_script(state, script, cfg, api_key)
                tag = "第1遍（冷）" if run_i == 1 else "第2遍（热，应命中缓存）"
                print("  %s" % tag)
                summaries.append(summarize("%s-%s" % (name, tag), results))
        else:
            results = run_script(state, script, cfg, api_key)
            summaries.append(summarize(name, results))

    # ---- 简洁对照 + 落盘 ----
    print_summary(summaries)
    path = save_runs(summaries, state_for_report, script)
    print("完整报告已存：%s" % path)


if __name__ == "__main__":
    main()
