"""
ai_verify ——「天」Agent AI 离线验证工具

在零游戏开发成本的条件下，验证 AI 能否稳定产出达标的叙事内容。
纯 Python 脚本，不依赖 Godot。

用法：python run_all.py
"""

import os

# ── 路径配置 ──
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
PROMPTS_DIR = os.path.join(PROJECT_ROOT, "prompts")
SCHEMAS_DIR = os.path.join(PROMPTS_DIR, "schemas")
FIXTURES_DIR = os.path.join(PROJECT_ROOT, "fixtures")
RESULTS_DIR = os.path.join(PROJECT_ROOT, "results")

# ── API 配置 ──
# 从环境变量读取，避免硬编码密钥
# 用法：export ANTHROPIC_API_KEY="sk-ant-..."  或  export OPENAI_API_KEY="sk-..."
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")

# 默认模型选择（"claude" | "openai"）
DEFAULT_PROVIDER = "claude"
DEFAULT_MODEL = "claude-sonnet-4-5-20250929"  # Claude Sonnet 4.5

# ── 验证参数 ──
V1_ITERATIONS = 30          # JSON 可靠性每种面具的测试次数
V2_DIALOGUE_TURNS = 20      # NPC 连续对话轮数
V3_TAROT_CARDS = 5          # 测试的塔罗牌数量
V3_CONTEXTS_PER_CARD = 3    # 每张牌的语境数
V5_CRACK_SCENARIOS = 3      # 裂缝触发场景数
V5_RUNS_PER_SCENARIO = 3    # 每种场景重复次数

# ── API 超时 ──
REQUEST_TIMEOUT = 30  # 秒
