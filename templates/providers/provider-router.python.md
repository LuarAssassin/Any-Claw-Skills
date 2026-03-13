# Provider: Provider Router (Python)

Template for multi-provider router with fallback chain and cost tracking.

## Generated File: `providers/router.py`

```python
"""Multi-provider router for {{PROJECT_NAME}}."""

import asyncio
import logging
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, AsyncIterator

logger = logging.getLogger(__name__)


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


# Cost per 1M tokens (input, output) in USD
COST_TABLE: dict[str, tuple[float, float]] = {
    "gpt-4o": (2.50, 10.00),
    "gpt-4o-mini": (0.15, 0.60),
    "gpt-4.1": (2.00, 8.00),
    "gpt-4.1-mini": (0.40, 1.60),
    "claude-sonnet-4-20250514": (3.00, 15.00),
    "claude-haiku-35-20241022": (0.80, 4.00),
    "claude-opus-4-20250514": (15.00, 75.00),
}


@dataclass
class UsageRecord:
    provider: str
    model: str
    prompt_tokens: int
    completion_tokens: int
    cost_usd: float
    latency_ms: float
    timestamp: float


@dataclass
class ProviderConfig:
    name: str
    provider: Provider
    models: list[str]
    priority: int = 0


class ProviderRouter(Provider):
    """Routes requests to providers with fallback and cost tracking."""

    def __init__(self, configs: list[ProviderConfig]):
        self._configs = sorted(configs, key=lambda c: c.priority)
        self._model_map: dict[str, ProviderConfig] = {}
        for cfg in self._configs:
            for model in cfg.models:
                self._model_map[model] = cfg
        self._usage: list[UsageRecord] = []

    def _resolve(self, model: str | None) -> list[ProviderConfig]:
        if model and model in self._model_map:
            cfg = self._model_map[model]
            others = [c for c in self._configs if c is not cfg]
            return [cfg] + others
        return list(self._configs)

    def _compute_cost(self, model: str, prompt: int, completion: int) -> float:
        rates = COST_TABLE.get(model)
        if not rates:
            return 0.0
        input_rate, output_rate = rates
        return (prompt * input_rate + completion * output_rate) / 1_000_000

    def _record(self, config: ProviderConfig, resp: Response, latency_ms: float):
        cost = self._compute_cost(
            resp.model,
            resp.usage.get("prompt_tokens", 0),
            resp.usage.get("completion_tokens", 0),
        )
        self._usage.append(UsageRecord(
            provider=config.name,
            model=resp.model,
            prompt_tokens=resp.usage.get("prompt_tokens", 0),
            completion_tokens=resp.usage.get("completion_tokens", 0),
            cost_usd=cost,
            latency_ms=latency_ms,
            timestamp=time.time(),
        ))

    async def chat(
        self,
        messages: list[Message],
        tools: list[ToolDef] | None = None,
        stream: bool = False,
        model: str | None = None,
    ) -> Response | AsyncIterator[str]:
        chain = self._resolve(model)
        last_error: Exception | None = None

        for cfg in chain:
            try:
                start = time.monotonic()
                result = await cfg.provider.chat(messages, tools=tools, stream=stream)
                elapsed = (time.monotonic() - start) * 1000

                if isinstance(result, Response):
                    self._record(cfg, result, elapsed)
                    return result
                return result

            except Exception as e:
                last_error = e
                logger.warning(
                    "Provider %s failed: %s. Trying next.", cfg.name, e
                )
                continue

        raise RuntimeError(
            f"All providers failed. Last error: {last_error}"
        )

    def get_total_cost(self) -> float:
        return sum(r.cost_usd for r in self._usage)

    def get_usage_summary(self) -> dict[str, Any]:
        by_provider: dict[str, dict[str, Any]] = {}
        for r in self._usage:
            if r.provider not in by_provider:
                by_provider[r.provider] = {
                    "requests": 0,
                    "total_tokens": 0,
                    "cost_usd": 0.0,
                    "avg_latency_ms": 0.0,
                }
            entry = by_provider[r.provider]
            entry["requests"] += 1
            entry["total_tokens"] += r.prompt_tokens + r.completion_tokens
            entry["cost_usd"] += r.cost_usd
        for name, entry in by_provider.items():
            records = [r for r in self._usage if r.provider == name]
            entry["avg_latency_ms"] = (
                sum(r.latency_ms for r in records) / len(records)
                if records else 0.0
            )
        return {
            "total_cost_usd": self.get_total_cost(),
            "total_requests": len(self._usage),
            "by_provider": by_provider,
        }
```

## Configuration

| Env Variable | Required | Description |
|---|---|---|
| `LLM_DEFAULT_PROVIDER` | No | Default provider name to route to |
| `LLM_FALLBACK_ENABLED` | No | Enable fallback chain (default: `true`) |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | Python package name |

## Usage Example

```python
from providers.openai_provider import OpenAIProvider
from providers.anthropic_provider import AnthropicProvider
from providers.router import ProviderRouter, ProviderConfig

router = ProviderRouter([
    ProviderConfig(
        name="anthropic",
        provider=AnthropicProvider(model="claude-sonnet-4-20250514"),
        models=["claude-sonnet-4-20250514", "claude-haiku-35-20241022"],
        priority=0,
    ),
    ProviderConfig(
        name="openai",
        provider=OpenAIProvider(model="gpt-4o"),
        models=["gpt-4o", "gpt-4o-mini"],
        priority=1,
    ),
])

response = await router.chat(messages, model="claude-sonnet-4-20250514")
print(router.get_usage_summary())
```
