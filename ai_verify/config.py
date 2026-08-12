"""
ai_verify ——「天」Agent AI 离线验证工具

在零游戏开发成本的条件下，验证 AI 能否稳定产出达标的叙事内容。
纯 Python 脚本，不依赖 Godot。

用法：python run_all.py
"""

import os
import sys

# Windows GBK 控制台编码修复 —— 强制 stdin/stdout/stderr 使用 UTF-8
if sys.platform == "win32":
    import io
    sys.stdin = io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8", errors="replace")
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")


def _load_env():
    """从 .env 文件加载环境变量（不覆盖已有的环境变量）"""
    env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    if not os.path.exists(env_path):
        return
    with open(env_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip()
            if key and value and key not in os.environ:
                os.environ[key] = value


_load_env()


# ── 路径配置 ──
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
PROMPTS_DIR = os.path.join(PROJECT_ROOT, "prompts")
SCHEMAS_DIR = os.path.join(PROMPTS_DIR, "schemas")
FIXTURES_DIR = os.path.join(PROJECT_ROOT, "fixtures")
RESULTS_DIR = os.path.join(PROJECT_ROOT, "results")

# ── API 配置 ──
# 从环境变量 / .env 读取，避免硬编码密钥
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
SILICONFLOW_API_KEY = os.environ.get("SILICONFLOW_API_KEY", "")
SILICONFLOW_BASE_URL = os.environ.get("SILICONFLOW_BASE_URL", "https://api.siliconflow.cn/v1")
SILICONFLOW_MODEL = os.environ.get("SILICONFLOW_MODEL", "deepseek-ai/DeepSeek-V3")

# 默认 provider 和模型
# 可选: "claude" | "openai" | "siliconflow"
DEFAULT_PROVIDER = os.environ.get("DEFAULT_PROVIDER", "siliconflow")

# 根据 provider 自动选默认模型
_DEFAULT_MODELS = {
    "claude": "claude-sonnet-4-5-20250929",
    "openai": "gpt-4o",
    "siliconflow": SILICONFLOW_MODEL,
}
DEFAULT_MODEL = os.environ.get(
    "DEFAULT_MODEL",
    _DEFAULT_MODELS.get(DEFAULT_PROVIDER, SILICONFLOW_MODEL),
)

# ── 验证参数 ──
V1_ITERATIONS = 3           # JSON 可靠性每种面具的测试次数 (quick test)
V2_DIALOGUE_TURNS = 5       # NPC 连续对话轮数 (quick test)
V3_TAROT_CARDS = 2          # 测试的塔罗牌数量 (quick test)
V3_CONTEXTS_PER_CARD = 2    # 每张牌的语境数 (quick test)
V5_CRACK_SCENARIOS = 3      # 裂缝触发场景数
V5_RUNS_PER_SCENARIO = 3    # 每种场景重复次数

# ── API 超时 ──
REQUEST_TIMEOUT = 90  # 秒 (DeepSeek-V3 长上下文响应可能超过 30s)
