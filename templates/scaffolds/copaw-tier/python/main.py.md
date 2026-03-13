# main.py.md

Template for the Standard/Python tier scaffold.

## Generated File: `__main__.py`

```python
"""{{PROJECT_NAME}} - {{PROJECT_DESCRIPTION}}

Entry point for the agent application.
Loads configuration, initializes the provider router, tool registry,
channel adapters, and runs the main agent loop with graceful shutdown.
"""

from __future__ import annotations

import asyncio
import logging
import signal
import sys
from typing import Any

import httpx

from {{PACKAGE_NAME}}.config import Settings

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

LOG_FORMAT = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
logger = logging.getLogger("{{PACKAGE_NAME}}")


# ---------------------------------------------------------------------------
# Provider router
# ---------------------------------------------------------------------------

class ProviderRouter:
    """Routes LLM calls to the configured provider (OpenAI-compatible)."""

    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self._settings = settings
        self._client = client

    async def complete(self, messages: list[dict[str, str]]) -> str:
        """Send a chat-completion request and return the assistant reply."""
        payload: dict[str, Any] = {
            "model": self._settings.provider_model,
            "messages": messages,
            "temperature": self._settings.provider_temperature,
        }
        resp = await self._client.post(
            f"{self._settings.provider_base_url}/chat/completions",
            headers={"Authorization": f"Bearer {self._settings.provider_api_key}"},
            json=payload,
            timeout=self._settings.provider_timeout,
        )
        resp.raise_for_status()
        data = resp.json()
        return data["choices"][0]["message"]["content"]


# ---------------------------------------------------------------------------
# Tool registry
# ---------------------------------------------------------------------------

class ToolRegistry:
    """Discovers and manages callable tools for the agent."""

    def __init__(self) -> None:
        self._tools: dict[str, Any] = {}

    def register(self, name: str, func: Any) -> None:
        self._tools[name] = func

    def list_tools(self) -> list[str]:
        return list(self._tools.keys())

    async def invoke(self, name: str, **kwargs: Any) -> Any:
        func = self._tools.get(name)
        if func is None:
            raise ValueError(f"Unknown tool: {name}")
        if asyncio.iscoroutinefunction(func):
            return await func(**kwargs)
        return func(**kwargs)


# ---------------------------------------------------------------------------
# Channel adapter
# ---------------------------------------------------------------------------

class ChannelAdapter:
    """Base adapter for inbound/outbound message channels."""

    def __init__(self, name: str, settings: Settings) -> None:
        self.name = name
        self._settings = settings
        self._queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()

    async def receive(self) -> dict[str, Any]:
        """Block until the next inbound message arrives."""
        return await self._queue.get()

    async def send(self, recipient: str, text: str) -> None:
        """Send an outbound message through this channel."""
        logger.info("[%s] -> %s: %s", self.name, recipient, text[:80])

    async def start(self) -> None:
        """Start listening for inbound events (override in subclass)."""
        logger.info("Channel %s started", self.name)

    async def stop(self) -> None:
        """Tear down the channel listener."""
        logger.info("Channel %s stopped", self.name)


# ---------------------------------------------------------------------------
# Agent loop
# ---------------------------------------------------------------------------

async def agent_loop(
    router: ProviderRouter,
    tools: ToolRegistry,
    channels: list[ChannelAdapter],
    shutdown_event: asyncio.Event,
) -> None:
    """Core loop: pull messages from channels, call the LLM, reply."""
    system_prompt = (
        "You are {{AGENT_PERSONA}}. "
        "Available tools: " + ", ".join(tools.list_tools()) + "."
    )

    async def handle_channel(channel: ChannelAdapter) -> None:
        await channel.start()
        try:
            while not shutdown_event.is_set():
                try:
                    msg = await asyncio.wait_for(channel.receive(), timeout=1.0)
                except asyncio.TimeoutError:
                    continue
                messages = [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": msg.get("text", "")},
                ]
                reply = await router.complete(messages)
                await channel.send(msg.get("sender", "unknown"), reply)
        finally:
            await channel.stop()

    tasks = [asyncio.create_task(handle_channel(ch)) for ch in channels]
    await shutdown_event.wait()
    for task in tasks:
        task.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)


# ---------------------------------------------------------------------------
# Shutdown handling
# ---------------------------------------------------------------------------

def _attach_signal_handlers(
    loop: asyncio.AbstractEventLoop,
    shutdown_event: asyncio.Event,
) -> None:
    """Register SIGINT / SIGTERM handlers for graceful shutdown."""
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, shutdown_event.set)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def async_main() -> None:
    settings = Settings()  # type: ignore[call-arg]

    logging.basicConfig(level=settings.log_level, format=LOG_FORMAT)
    logger.info("Starting {{PROJECT_NAME}}")

    shutdown_event = asyncio.Event()
    _attach_signal_handlers(asyncio.get_running_loop(), shutdown_event)

    async with httpx.AsyncClient() as client:
        router = ProviderRouter(settings, client)

        tools = ToolRegistry()
        # -- register project-specific tools here --
        # tools.register("search", search_func)

        channels: list[ChannelAdapter] = []
        for ch_name in settings.enabled_channels:
            channels.append(ChannelAdapter(ch_name, settings))

        logger.info(
            "Initialized: provider=%s, channels=%s, tools=%s",
            settings.provider_model,
            [c.name for c in channels],
            tools.list_tools(),
        )

        await agent_loop(router, tools, channels, shutdown_event)

    logger.info("{{PROJECT_NAME}} shut down cleanly")


def main() -> None:
    try:
        asyncio.run(async_main())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Human-readable project name (e.g. "My Assistant") |
| `{{PROJECT_DESCRIPTION}}` | One-line description for the module docstring |
| `{{PACKAGE_NAME}}` | Python package name used in imports (e.g. `my_assistant`) |
| `{{AGENT_PERSONA}}` | System-prompt persona description for the LLM |
