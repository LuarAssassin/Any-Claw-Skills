# slack.python.md

Slack channel adapter using `slack-bolt`. Supports socket mode and HTTP mode, message/app_mention events, and Block Kit responses.

## Generated File: `{{PACKAGE_NAME}}/channels/slack.py`

```python
"""{{PROJECT_NAME}} - Slack channel adapter.

Connects to Slack via Bolt framework.
Supports Socket Mode (development) and HTTP mode (production).
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine, Optional

from slack_bolt.async_app import AsyncApp
from slack_bolt.adapter.socket_mode.async_handler import AsyncSocketModeHandler
from slack_sdk.web.async_client import AsyncWebClient

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Unified message types (shared across all channels)
# ---------------------------------------------------------------------------

class ContentType(Enum):
    TEXT = "text"
    IMAGE = "image"
    FILE = "file"


@dataclass
class ContentPart:
    type: ContentType
    text: Optional[str] = None
    url: Optional[str] = None
    mime_type: Optional[str] = None
    filename: Optional[str] = None
    data: Optional[bytes] = None


@dataclass
class Message:
    content: list[ContentPart]
    sender_id: str
    sender_name: str
    channel: str = "slack"
    session_id: str = ""
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def text(self) -> str:
        parts = [p.text for p in self.content if p.type == ContentType.TEXT and p.text]
        return "\n".join(parts)


ProcessHandler = Callable[[Message], Coroutine[Any, Any, str]]


# ---------------------------------------------------------------------------
# Channel adapter base
# ---------------------------------------------------------------------------

class ChannelAdapter:
    """Base class for all channel adapters."""

    async def start(self) -> None:
        raise NotImplementedError

    async def stop(self) -> None:
        raise NotImplementedError

    async def send_message(self, recipient_id: str, text: str, **kwargs: Any) -> None:
        raise NotImplementedError


# ---------------------------------------------------------------------------
# Slack adapter
# ---------------------------------------------------------------------------

@dataclass
class SlackConfig:
    bot_token: str
    app_token: str = ""                # Required for Socket Mode
    signing_secret: str = ""           # Required for HTTP mode
    mode: str = "socket"               # "socket" or "http"
    http_port: int = 3000


class SlackChannel(ChannelAdapter):
    """Slack bot channel adapter."""

    def __init__(self, config: SlackConfig, process: ProcessHandler) -> None:
        self._config = config
        self._process = process
        self._app: Optional[AsyncApp] = None
        self._handler: Optional[AsyncSocketModeHandler] = None

    # -- Lifecycle -----------------------------------------------------------

    async def start(self) -> None:
        self._app = AsyncApp(
            token=self._config.bot_token,
            signing_secret=self._config.signing_secret or "not-used-in-socket-mode",
        )

        self._app.event("message")(self._handle_message_event)
        self._app.event("app_mention")(self._handle_mention_event)

        if self._config.mode == "socket":
            self._handler = AsyncSocketModeHandler(self._app, self._config.app_token)
            await self._handler.start_async()
            logger.info("Slack socket mode started")
        else:
            # HTTP mode: start the built-in server
            await self._app.start_async(port=self._config.http_port)
            logger.info("Slack HTTP mode started on port %d", self._config.http_port)

    async def stop(self) -> None:
        if self._handler:
            await self._handler.close_async()
        if self._app:
            await self._app.stop_async()
        logger.info("Slack channel stopped")

    async def send_message(
        self,
        recipient_id: str,
        text: str,
        *,
        blocks: Optional[list[dict[str, Any]]] = None,
        thread_ts: Optional[str] = None,
        **kwargs: Any,
    ) -> None:
        """Send a message to a Slack channel, optionally with Block Kit blocks."""
        if not self._app:
            raise RuntimeError("Channel not started")

        send_kwargs: dict[str, Any] = {
            "channel": recipient_id,
            "text": text,
        }
        if blocks:
            send_kwargs["blocks"] = blocks
        if thread_ts:
            send_kwargs["thread_ts"] = thread_ts

        await self._app.client.chat_postMessage(**send_kwargs)

    # -- Event handlers ------------------------------------------------------

    async def _handle_message_event(self, event: dict, say: Any) -> None:
        """Handle direct messages and channel messages (non-mention)."""
        # Skip bot messages, message_changed, etc.
        if event.get("subtype"):
            return
        if event.get("bot_id"):
            return

        msg = self._convert_event(event)
        reply = await self._process(msg)

        blocks = self._build_response_blocks(reply)
        await say(text=reply, blocks=blocks, thread_ts=event.get("thread_ts"))

    async def _handle_mention_event(self, event: dict, say: Any) -> None:
        """Handle @mentions of the bot."""
        msg = self._convert_event(event)
        reply = await self._process(msg)

        blocks = self._build_response_blocks(reply)
        await say(text=reply, blocks=blocks, thread_ts=event.get("ts"))

    # -- Conversion ----------------------------------------------------------

    def _convert_event(self, event: dict) -> Message:
        """Convert a Slack event dict into a unified Message."""
        parts: list[ContentPart] = []

        text = event.get("text", "")
        if text:
            parts.append(ContentPart(type=ContentType.TEXT, text=text))

        for file_info in event.get("files", []):
            mime = file_info.get("mimetype", "application/octet-stream")
            if mime.startswith("image/"):
                parts.append(ContentPart(
                    type=ContentType.IMAGE,
                    url=file_info.get("url_private"),
                    mime_type=mime,
                    filename=file_info.get("name"),
                ))
            else:
                parts.append(ContentPart(
                    type=ContentType.FILE,
                    url=file_info.get("url_private"),
                    mime_type=mime,
                    filename=file_info.get("name"),
                ))

        return Message(
            content=parts,
            sender_id=event.get("user", ""),
            sender_name=event.get("user", ""),
            session_id=event.get("channel", ""),
            metadata={
                "thread_ts": event.get("thread_ts"),
                "team": event.get("team"),
            },
        )

    @staticmethod
    def _build_response_blocks(text: str) -> list[dict[str, Any]]:
        """Wrap response text in a Block Kit section block."""
        return [
            {
                "type": "section",
                "text": {"type": "mrkdwn", "text": text[:3000]},
            }
        ]
```

## Configuration

Environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `SLACK_BOT_TOKEN` | Yes | Bot User OAuth Token (`xoxb-...`) |
| `SLACK_APP_TOKEN` | Socket mode | App-Level Token (`xapp-...`) |
| `SLACK_SIGNING_SECRET` | HTTP mode | Signing secret from app settings |
| `SLACK_MODE` | No | `socket` (default) or `http` |
| `SLACK_HTTP_PORT` | No | HTTP listen port (default `3000`) |

`.env.example`:

```env
SLACK_BOT_TOKEN=xoxb-your-token
SLACK_APP_TOKEN=xapp-your-app-token
SLACK_SIGNING_SECRET=
SLACK_MODE=socket
SLACK_HTTP_PORT=3000
```

## Dependencies

```
slack-bolt>=1.18
slack-sdk>=3.27
```

## Usage

```python
import asyncio
import os
from {{PACKAGE_NAME}}.channels.slack import SlackChannel, SlackConfig


async def handle_message(msg):
    """Replace with your agent logic."""
    return f"Echo: {msg.text}"


async def main():
    config = SlackConfig(
        bot_token=os.environ["SLACK_BOT_TOKEN"],
        app_token=os.getenv("SLACK_APP_TOKEN", ""),
        signing_secret=os.getenv("SLACK_SIGNING_SECRET", ""),
        mode=os.getenv("SLACK_MODE", "socket"),
    )

    channel = SlackChannel(config=config, process=handle_message)
    await channel.start()

    try:
        await asyncio.Event().wait()
    finally:
        await channel.stop()


if __name__ == "__main__":
    asyncio.run(main())
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Project display name |
| `{{PACKAGE_NAME}}` | Python package name (e.g. `my_assistant`) |
