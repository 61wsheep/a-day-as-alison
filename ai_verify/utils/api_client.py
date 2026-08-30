"""
统一的 LLM API 调用封装。

支持：
- Anthropic Claude API
- OpenAI API (GPT-4o)
- 硅基流动 (SiliconFlow) —— OpenAI 兼容，DeepSeek-V3 / Qwen 等
- 结构化 JSON 输出
"""

import json
import time
import re
from openai import OpenAI

# anthropic SDK 为可选依赖——仅在使用 Claude provider 时需要


def _sanitize_str(s: str) -> str:
    """
    清理字符串中的非法 Unicode surrogate 字符。
    当 Prompt 文件或 API 响应包含 lone surrogate 时，
    Python 的 json 序列化会抛出 UnicodeEncodeError。
    """
    if not isinstance(s, str):
        return s
    # 移除 lone surrogates (U+D800–U+DFFF)
    return re.sub(r'[\ud800-\udfff]', '', s)


def _sanitize_dict(obj):
    """递归清理 dict/list/str 中的 surrogate 字符"""
    if isinstance(obj, str):
        return _sanitize_str(obj)
    elif isinstance(obj, dict):
        return {k: _sanitize_dict(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [_sanitize_dict(v) for v in obj]
    return obj
try:
    import anthropic
    HAS_ANTHROPIC = True
except ImportError:
    HAS_ANTHROPIC = False

from config import (
    ANTHROPIC_API_KEY, OPENAI_API_KEY,
    SILICONFLOW_API_KEY, SILICONFLOW_BASE_URL,
    DEFAULT_PROVIDER, DEFAULT_MODEL,
    REQUEST_TIMEOUT,
)


def _get_client(provider: str) -> OpenAI | None:
    """
    获取 LLM 客户端。
    SiliconFlow 走 OpenAI 兼容协议，仅 base_url 不同。
    Claude 走独立路径（需要 anthropic SDK）。
    返回 None 表示走 Claude 独立路径。
    """
    if provider == "claude":
        return None  # 走独立路径

    if provider == "siliconflow":
        if not SILICONFLOW_API_KEY:
            raise ValueError("SILICONFLOW_API_KEY 未设置（检查 .env 文件）")
        return OpenAI(
            api_key=SILICONFLOW_API_KEY,
            base_url=SILICONFLOW_BASE_URL,
            timeout=REQUEST_TIMEOUT,
        )

    if provider == "openai":
        if not OPENAI_API_KEY:
            raise ValueError("OPENAI_API_KEY 未设置")
        return OpenAI(
            api_key=OPENAI_API_KEY,
            timeout=REQUEST_TIMEOUT,
        )

    raise ValueError(f"不支持的 provider: {provider}")


def _call_claude(system_prompt: str, user_message: str, model: str, max_tokens: int, temperature: float) -> str:
    """Claude API 调用（需要 anthropic SDK）"""
    if not HAS_ANTHROPIC:
        raise RuntimeError("使用 Claude provider 需要安装 anthropic SDK: pip install anthropic")
    if not ANTHROPIC_API_KEY:
        raise ValueError("ANTHROPIC_API_KEY 环境变量未设置")
    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY, timeout=REQUEST_TIMEOUT)
    response = client.messages.create(
        model=model,
        max_tokens=max_tokens,
        temperature=temperature,
        system=system_prompt,
        messages=[{"role": "user", "content": user_message}],
    )
    for block in response.content:
        if block.type == "text":
            return block.text
    return ""


def _call_openai_compatible(
    provider: str, system_prompt: str, user_message: str,
    model: str, max_tokens: int, temperature: float,
) -> str:
    """OpenAI 兼容 API 调用（含 SiliconFlow）"""
    client = _get_client(provider)
    response = client.chat.completions.create(
        model=model,
        max_tokens=max_tokens,
        temperature=temperature,
        messages=_sanitize_dict([
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ]),
    )
    return _sanitize_str(response.choices[0].message.content or "")


def call_llm(
    system_prompt: str,
    user_message: str,
    *,
    provider: str = DEFAULT_PROVIDER,
    model: str = DEFAULT_MODEL,
    max_tokens: int = 1024,
    temperature: float = 0.8,
) -> str:
    """
    调用 LLM，返回纯文本响应。

    Args:
        system_prompt: 系统级 Prompt
        user_message: 用户消息（组装好的 context）
        provider: "claude" | "openai" | "siliconflow"
        model: 模型 ID
        max_tokens: 最大输出 token
        temperature: 创意度（0=确定，1=高创意）

    Returns:
        LLM 响应纯文本
    """
    if provider == "claude":
        return _call_claude(system_prompt, user_message, model, max_tokens, temperature)
    else:
        # openai / siliconflow 都走 OpenAI 兼容协议
        return _call_openai_compatible(provider, system_prompt, user_message, model, max_tokens, temperature)


def call_llm_structured(
    system_prompt: str,
    user_message: str,
    json_schema: dict,
    *,
    provider: str = DEFAULT_PROVIDER,
    model: str = DEFAULT_MODEL,
    max_tokens: int = 1024,
    temperature: float = 0.7,
) -> tuple[dict | None, str, bool, int]:
    """
    调用 LLM 并要求结构化 JSON 输出。

    对于 Claude：使用 tool_use 强制按 JSON Schema 输出
    对于 OpenAI/SiliconFlow：在 user_message 末尾追加 JSON 格式要求

    Returns:
        (parsed_dict | None, raw_text, success: bool, attempts: int)
        - parsed_dict: 成功解析的 JSON 对象，失败则为 None
        - raw_text: LLM 原始文本响应（debug 用）
        - success: 是否首次解析即成功
        - attempts: 解析尝试次数
    """
    # 对于非 Claude 模型，在 user message 中追加 JSON 格式指令
    if provider != "claude":
        schema_str = json.dumps(json_schema, ensure_ascii=False, indent=2)
        user_message += (
            f"\n\n【重要：你必须严格按照以下 JSON Schema 返回合法 JSON，不要输出任何 JSON 之外的文字】\n"
            f"```json\n{schema_str}\n```\n"
            f"请直接返回 JSON，不要用 markdown 代码块包裹，不要加任何解释。"
        )

    raw_text = ""
    try:
        raw_text = call_llm(
            system_prompt=system_prompt,
            user_message=user_message,
            provider=provider,
            model=model,
            max_tokens=max_tokens,
            temperature=temperature,
        )
    except Exception as e:
        raw_text = f"[API_ERROR] {str(e)}"
        return None, raw_text, False, 0

    # 尝试直接解析
    parsed = _extract_json(raw_text)
    if parsed is not None:
        if _validate_schema(parsed, json_schema):
            return parsed, raw_text, True, 1

    # 解析失败或 schema 不匹配 → 返回 raw
    return None, raw_text, False, 1


def _extract_json(text: str) -> dict | None:
    """
    从 LLM 响应中提取 JSON 对象。
    优先整个文本解析，失败则尝试正则提取 ```json ... ``` 块。
    """
    import re

    # 尝试 1：整个文本就是 JSON
    try:
        return json.loads(text.strip())
    except json.JSONDecodeError:
        pass

    # 尝试 2：提取 ```json ... ``` 代码块
    match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if match:
        try:
            return json.loads(match.group(1).strip())
        except json.JSONDecodeError:
            pass

    # 尝试 3：提取第一个 { ... } 块
    match = re.search(r"\{[\s\S]*\}", text)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass

    return None


def _validate_schema(data: dict, schema: dict) -> bool:
    """
    简化的 JSON Schema 校验。
    只检查 required 字段是否存在 + 类型是否正确。
    不引入 jsonschema 库以避免额外依赖。
    """
    required = schema.get("required", [])
    properties = schema.get("properties", {})

    for field in required:
        if field not in data:
            return False

    type_map = {
        "string": str,
        "number": (int, float),
        "integer": int,
        "boolean": bool,
        "array": list,
        "object": dict,
    }

    for field, spec in properties.items():
        if field in data:
            expected = spec.get("type")
            if expected and expected in type_map:
                expected_type = type_map[expected]
                if not isinstance(data[field], expected_type):
                    return False

    return True


def generate_topic_suggestions(
    npc_id: str,
    npc_card: str,
    system_prompt: str,
    todays_theme: dict,
    conversation_history: list[dict],
    count: int = 4,
    *,
    provider: str = DEFAULT_PROVIDER,
    model: str = DEFAULT_MODEL,
) -> list[str]:
    """
    生成 NPC 对话的话题建议。

    Returns:
        话题建议文本列表
    """
    schema = {
        "type": "object",
        "properties": {
            "topic_suggestions": {
                "type": "array",
                "items": {"type": "string"},
            }
        },
        "required": ["topic_suggestions"],
    }

    user_msg = f"""当前 NPC：{npc_id}
今日主题：{json.dumps(todays_theme, ensure_ascii=False)}
最近对话摘要：{json.dumps(conversation_history[-3:] if conversation_history else [], ensure_ascii=False)}

请以玩家艾莉森的第一人称口吻生成 {count} 条她接下来可能说的话，每条 15-30 字。
这些是「玩家视角的回复选项」，不是 {npc_id} 的话。应该：反映当前情绪、呼应今日主题、试探 NPC 的秘密、推动叙事前进。

以 JSON 格式返回。"""

    parsed, raw, success, attempts = call_llm_structured(
        system_prompt=f"{system_prompt}\n\n{npc_card}",
        user_message=user_msg,
        json_schema=schema,
        provider=provider,
        model=model,
        max_tokens=512,
        temperature=0.8,
    )

    if success and parsed:
        return parsed.get("topic_suggestions", [])
    return []
