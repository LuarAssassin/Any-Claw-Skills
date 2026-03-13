# Provider: OpenAI (Python)

Template for OpenAI LLM provider integration using the official `openai` SDK.

## Generated File: `providers/openai_provider.py`

```python
"""OpenAI LLM provider for {{PROJECT_NAME}}."""

import asyncio
import json
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, AsyncIterator

import tiktoken
from openai import AsyncOpenAI, APIError, RateLimitError


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


class OpenAIProvider(Provider):
    """OpenAI chat completions with streaming, tool calling, and retry."""

    def __init__(
        self,
        api_key: str | None = None,
        model: str = "gpt-4o",
        base_url: str | None = None,
        max_retries: int = 3,
        timeout: float = 60.0,
    ):
        self.model = model
        self.max_retries = max_retries
        self.client = AsyncOpenAI(
            api_key=api_key,
            base_url=base_url,
            timeout=timeout,
        )
        self._encoding = None

    def count_tokens(self, text: str) -> int:
        if self._encoding is None:
            try:
                self._encoding = tiktoken.encoding_for_model(self.model)
            except KeyError:
                self._encoding = tiktoken.get_encoding("cl100k_base")
        return len(self._encoding.encode(text))

    def _build_tools(self, tools: list[ToolDef] | None) -> list[dict] | None:
        if not tools:
            return None
        return [
            {
                "type": "function",
                "function": {
                    "name": t.name,
                    "description": t.description,
                    "parameters": t.parameters,
                },
            }
            for t in tools
        ]

    def _format_messages(self, messages: list[Message]) -> list[dict]:
        formatted = []
        for m in messages:
            msg: dict[str, Any] = {"role": m.role, "content": m.content}
            if m.tool_calls:
                msg["tool_calls"] = m.tool_calls
            if m.tool_call_id:
                msg["tool_call_id"] = m.tool_call_id
            formatted.append(msg)
        return formatted

    async def _call_with_retry(self, **kwargs) -> Any:
        last_error = None
        for attempt in range(self.max_retries):
            try:
                return await self.client.chat.completions.create(**kwargs)
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
        params = {
            "model": self.model,
            "messages": self._format_messages(messages),
        }
        tool_defs = self._build_tools(tools)
        if tool_defs:
            params["tools"] = tool_defs

        if stream:
            return self._stream(params)

        resp = await self._call_with_retry(**params)
        choice = resp.choices[0]
        tc = []
        if choice.message.tool_calls:
            tc = [
                {
                    "id": t.id,
                    "function": {"name": t.function.name, "arguments": t.function.arguments},
                }
                for t in choice.message.tool_calls
            ]
        return Response(
            content=choice.message.content or "",
            tool_calls=tc,
            usage={
                "prompt_tokens": resp.usage.prompt_tokens,
                "completion_tokens": resp.usage.completion_tokens,
                "total_tokens": resp.usage.total_tokens,
            },
            model=resp.model,
            finish_reason=choice.finish_reason,
        )

    async def _stream(self, params: dict) -> AsyncIterator[str]:
        params["stream"] = True
        resp = await self._call_with_retry(**params)
        async for chunk in resp:
            if chunk.choices and chunk.choices[0].delta.content:
                yield chunk.choices[0].delta.content
```

## Configuration

| Env Variable | Required | Description |
|---|---|---|
| `OPENAI_API_KEY` | Yes | OpenAI API key (read automatically by SDK) |
| `OPENAI_BASE_URL` | No | Override base URL for OpenAI-compatible APIs |
| `OPENAI_ORG_ID` | No | Organization ID for API requests |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | Python package name |

## Dependencies

```
openai>=1.0.0
tiktoken>=0.5.0
```
