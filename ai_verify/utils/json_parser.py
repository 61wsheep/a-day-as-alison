"""
JSON 解析 + 多重恢复策略。

每个 AI 调用点需要独立兜底：JSON Schema 校验 → 正则提取 → 预制文本回退
"""

import json
import re
from dataclasses import dataclass, field


@dataclass
class ParseResult:
    """JSON 解析结果"""
    success: bool
    parsed: dict | None = None
    raw_text: str = ""
    recovery_method: str = "none"  # "direct" | "regex_code_block" | "regex_braces" | "failed"
    error_message: str = ""


def parse_json_response(raw_text: str, expected_schema: dict | None = None) -> ParseResult:
    """
    从 LLM 原始响应中解析 JSON，使用三层恢复策略。

    Args:
        raw_text: LLM 返回的原始文本
        expected_schema: 可选的 JSON Schema（用于校验必需字段）

    Returns:
        ParseResult
    """
    if not raw_text or not raw_text.strip():
        return ParseResult(
            success=False,
            raw_text=raw_text,
            recovery_method="failed",
            error_message="空响应",
        )

    text = raw_text.strip()

    # ── 第 1 层：直接 JSON 解析 ──
    try:
        parsed = json.loads(text)
        if expected_schema:
            _check_required_fields(parsed, expected_schema)  # 不抛异常则通过
        return ParseResult(
            success=True, parsed=parsed, raw_text=raw_text, recovery_method="direct",
        )
    except (json.JSONDecodeError, MissingFieldError) as e:
        last_error = str(e)

    # ── 第 2 层：提取 ```json ... ``` 代码块 ──
    match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if match:
        try:
            parsed = json.loads(match.group(1).strip())
            if expected_schema:
                _check_required_fields(parsed, expected_schema)
            return ParseResult(
                success=True, parsed=parsed, raw_text=raw_text,
                recovery_method="regex_code_block",
            )
        except (json.JSONDecodeError, MissingFieldError) as e:
            last_error = str(e)

    # ── 第 3 层：提取第一个 { ... } 块 ──
    match = re.search(r"\{[\s\S]*\}", text)
    if match:
        try:
            parsed = json.loads(match.group(0))
            if expected_schema:
                _check_required_fields(parsed, expected_schema)
            return ParseResult(
                success=True, parsed=parsed, raw_text=raw_text,
                recovery_method="regex_braces",
            )
        except (json.JSONDecodeError, MissingFieldError) as e:
            last_error = str(e)

    # ── 全部失败 ──
    return ParseResult(
        success=False,
        raw_text=raw_text,
        recovery_method="failed",
        error_message=last_error,
    )


class MissingFieldError(Exception):
    """JSON 缺少必需字段"""
    pass


def _check_required_fields(data: dict, schema: dict) -> None:
    """检查 JSON 是否包含 schema 中声明的 required 字段"""
    required = schema.get("required", [])
    for field in required:
        if field not in data:
            raise MissingFieldError(f"缺少必需字段: {field}")


def safe_get(data: dict | None, key: str, default=None):
    """安全取值，data 可能为 None"""
    if data is None:
        return default
    return data.get(key, default)
