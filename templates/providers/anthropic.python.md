# Provider: Anthropic (Python)

Template for Anthropic LLM provider integration using the official `anthropic` SDK.

## Generated File: `providers/anthropic_provider.py`

```python
"""Anthropic LLM provider for {{PROJECT_NAME}}."""

import asyncio
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, AsyncIterator

from anthropic import AsyncAnthropic, APIError, RateLimitError


@dataclass
class Message:
    role: str
    content: str
    tool_calls: list[dict[str, Any]] | None = None
    tool_call_id: str | None = None


@dataclass
class ToolDef:
    name: str
    description: str
    parameters: dict[str, Any]


@dataclass
class Response:
    content: str
    tool_calls: list[dict[str, Any]]
    usage: dict[str, int]
    model: str
    finish_reason: str


class Provider(ABC):
    @abstractmethod
    async def chat(
        self,
        messages: list[Message],
        tools: list[ToolDef] | None = None,
        stream: bool = False,
    ) -> Response | AsyncIterator[str]:
        ...


class AnthropicProvider(Provider):
    """Anthropic Messages API with streaming and tool use."""

    def __init__(
        self,
        api_key: str | None = None,
        model: str = "claude-sonnet-4-20250514",
        max_tokens: int = 4096,
        max_retries: int = 3,
        timeout: float = 60.0,
    ):
        self.model = model
        self.max_tokens = max_tokens
        self.max_retries = max_retries
        self.client = AsyncAnthropic(
            api_key=api_key,
            timeout=timeout,
        )

    def _build_tools(self, tools: list[ToolDef] | None) -> list[dict] | None:
        if not tools:
            return None
        return [
            {
                "name": t.name,
                "description": t.description,
                "input_schema": t.parameters,
            }
            for t in tools
        ]

    def _format_messages(self, messages: list[Message]) -> tuple[str | None, list[dict]]:
        system = None
        formatted = []
        for m in messages:
            if m.role == "system":
                system = m.content
                continue
            if m.role == "tool":
                formatted.append({
                    "role": "user",
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": m.tool_call_id,
                            "content": m.content,
                        }
                    ],
                })
                continue
            if m.tool_calls:
                content = []
                if m.content:
                    content.append({"type": "text", "text": m.content})
                for tc in m.tool_calls:
                    import json
                    args = tc["function"]["arguments"]
                    if isinstance(args, str):
                        args = json.loads(args)
                    content.append({
                        "type": "tool_use",
                        "id": tc["id"],
                        "name": tc["function"]["name"],
                        "input": args,
                    })
                formatted.append({"role": "assistant", "content": content})
            else:
                formatted.append({"role": m.role, "content": m.content})
        return system, formatted

    async def _call_with_retry(self, **kwargs) -> Any:
        last_error = None
        for attempt in range(self.max_retries):
            try:
                return await self.client.messages.create(**kwargs)
            except RateLimitError as e:
                last_error = e
                wait = min(2**attempt, 16)
                await asyncio.sleep(wait)
            except APIError as e:
                if e.status_code and e.status_code >= 500:
                    last_error = e
                    wait = min(2**attempt, 16)
                    await asyncio.sleep(wait)
                else:
                    raise
        raise last_error

    async def chat(
        self,
        messages: list[Message],
        tools: list[ToolDef] | None = None,
        stream: bool = False,
    ) -> Response | AsyncIterator[str]:
        system, formatted = self._format_messages(messages)
        params: dict[str, Any] = {
            "model": self.model,
            "max_tokens": self.max_tokens,
            "messages": formatted,
        }
        if system:
            params["system"] = system
        tool_defs = self._build_tools(tools)
        if tool_defs:
            params["tools"] = tool_defs

        if stream:
            return self._stream(params)

        resp = await self._call_with_retry(**params)
        content = ""
        tc = []
        for block in resp.content:
            if block.type == "text":
                content += block.text
            elif block.type == "tool_use":
                tc.append({
                    "id": block.id,
                    "function": {"name": block.name, "arguments": block.input},
                })
        return Response(
            content=content,
            tool_calls=tc,
            usage={
                "prompt_tokens": resp.usage.input_tokens,
                "completion_tokens": resp.usage.output_tokens,
                "total_tokens": resp.usage.input_tokens + resp.usage.output_tokens,
            },
            model=resp.model,
            finish_reason=resp.stop_reason or "end_turn",
        )

    async def _stream(self, params: dict) -> AsyncIterator[str]:
        params["stream"] = True
        resp = await self._call_with_retry(**params)
        async for event in resp:
            if event.type == "content_block_delta" and event.delta.type == "text_delta":
                yield event.delta.text
```

## Configuration

| Env Variable | Required | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key (read automatically by SDK) |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | Python package name |

## Dependencies

```
anthropic>=0.39.0
```
