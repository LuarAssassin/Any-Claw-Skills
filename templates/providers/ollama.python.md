# Provider: Ollama (Python)

Template for Ollama local LLM provider integration using HTTP client.

## Generated File: `providers/ollama_provider.py`

```python
"""Ollama local LLM provider for {{PROJECT_NAME}}."""

import json
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, AsyncIterator

import httpx


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


class OllamaProvider(Provider):
    """Ollama local inference with streaming and model management."""

    def __init__(
        self,
        base_url: str = "http://localhost:11434",
        model: str = "llama3.1",
        timeout: float = 120.0,
    ):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.timeout = timeout

    async def _request(self, path: str, body: dict, stream: bool = False) -> Any:
        url = f"{self.base_url}{path}"
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            if stream:
                return client.stream("POST", url, json=body)
            resp = await client.post(url, json=body)
            resp.raise_for_status()
            return resp.json()

    async def list_models(self) -> list[dict[str, Any]]:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            resp = await client.get(f"{self.base_url}/api/tags")
            resp.raise_for_status()
            data = resp.json()
        return data.get("models", [])

    async def pull_model(self, model: str | None = None) -> AsyncIterator[dict]:
        target = model or self.model
        async with httpx.AsyncClient(timeout=600.0) as client:
            async with client.stream(
                "POST",
                f"{self.base_url}/api/pull",
                json={"name": target},
            ) as resp:
                resp.raise_for_status()
                async for line in resp.aiter_lines():
                    if line.strip():
                        yield json.loads(line)

    def _format_messages(self, messages: list[Message]) -> list[dict]:
        return [{"role": m.role, "content": m.content} for m in messages]

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

    async def chat(
        self,
        messages: list[Message],
        tools: list[ToolDef] | None = None,
        stream: bool = False,
    ) -> Response | AsyncIterator[str]:
        body: dict[str, Any] = {
            "model": self.model,
            "messages": self._format_messages(messages),
            "stream": stream,
        }
        tool_defs = self._build_tools(tools)
        if tool_defs:
            body["tools"] = tool_defs

        if stream:
            return self._stream(body)

        data = await self._request("/api/chat", body)
        msg = data.get("message", {})
        tc = []
        for call in msg.get("tool_calls", []):
            fn = call.get("function", {})
            tc.append({
                "id": f"call_{fn.get('name', 'unknown')}",
                "function": {
                    "name": fn.get("name", ""),
                    "arguments": json.dumps(fn.get("arguments", {})),
                },
            })
        return Response(
            content=msg.get("content", ""),
            tool_calls=tc,
            usage={
                "prompt_tokens": data.get("prompt_eval_count", 0),
                "completion_tokens": data.get("eval_count", 0),
                "total_tokens": data.get("prompt_eval_count", 0) + data.get("eval_count", 0),
            },
            model=data.get("model", self.model),
            finish_reason=data.get("done_reason", "stop"),
        )

    async def _stream(self, body: dict) -> AsyncIterator[str]:
        url = f"{self.base_url}/api/chat"
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            async with client.stream("POST", url, json=body) as resp:
                resp.raise_for_status()
                async for line in resp.aiter_lines():
                    if not line.strip():
                        continue
                    data = json.loads(line)
                    content = data.get("message", {}).get("content", "")
                    if content:
                        yield content
```

## Configuration

| Env Variable | Required | Description |
|---|---|---|
| `OLLAMA_HOST` | No | Ollama server URL (default: `http://localhost:11434`) |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | Python package name |

## Dependencies

```
httpx>=0.25.0
```
