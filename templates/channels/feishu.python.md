# feishu.python.md

Feishu/Lark channel adapter. Supports event subscription and interactive card messages.

## Generated File: `{{PACKAGE_NAME}}/channels/feishu.py`

```python
"""{{PROJECT_NAME}} - Feishu/Lark channel adapter.

Connects to Feishu via event subscription (HTTP callback).
Supports text messages, card message replies, and media handling.
"""

from __future__ import annotations

import hashlib
import json
import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine, Optional

import httpx
from aiohttp import web

logger = logging.getLogger(__name__)

API_BASE = "https://open.feishu.cn/open-apis"


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
    channel: str = "feishu"
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
# Feishu adapter
# ---------------------------------------------------------------------------

@dataclass
class FeishuConfig:
    app_id: str
    app_secret: str
    verification_token: str = ""       # For event verification (v1)
    encrypt_key: str = ""              # For event decryption
    webhook_port: int = 9000
    webhook_path: str = "/feishu/event"


class FeishuChannel(ChannelAdapter):
    """Feishu/Lark bot channel adapter."""

    def __init__(self, config: FeishuConfig, process: ProcessHandler) -> None:
        self._config = config
        self._process = process
        self._http: Optional[httpx.AsyncClient] = None
        self._runner: Optional[web.AppRunner] = None
        self._site: Optional[web.TCPSite] = None
        self._tenant_token: str = ""
        self._token_expires: float = 0.0
        self._seen_message_ids: set[str] = set()  # Deduplication

    # -- Lifecycle -----------------------------------------------------------

    async def start(self) -> None:
        self._http = httpx.AsyncClient(timeout=30.0)
        await self._refresh_token()

        app = web.Application()
        app.router.add_post(self._config.webhook_path, self._handle_event)

        self._runner = web.AppRunner(app)
        await self._runner.setup()
        self._site = web.TCPSite(self._runner, "0.0.0.0", self._config.webhook_port)
        await self._site.start()
        logger.info(
            "Feishu event listener on port %d%s",
            self._config.webhook_port,
            self._config.webhook_path,
        )

    async def stop(self) -> None:
        if self._http:
            await self._http.aclose()
        if self._site:
            await self._site.stop()
        if self._runner:
            await self._runner.cleanup()
        logger.info("Feishu channel stopped")

    async def send_message(
        self,
        recipient_id: str,
        text: str,
        *,
        receive_id_type: str = "open_id",
        msg_type: str = "text",
        **kwargs: Any,
    ) -> None:
        """Send a text message to a user or chat."""
        token = await self._ensure_token()
        payload = {
            "receive_id": recipient_id,
            "msg_type": msg_type,
            "content": json.dumps({"text": text}),
        }

        resp = await self._http.post(
            f"{API_BASE}/im/v1/messages",
            params={"receive_id_type": receive_id_type},
            headers={"Authorization": f"Bearer {token}"},
            json=payload,
        )
        resp.raise_for_status()

    # -- Card messages -------------------------------------------------------

    async def send_card(
        self,
        recipient_id: str,
        title: str,
        content: str,
        *,
        buttons: Optional[list[dict[str, str]]] = None,
        receive_id_type: str = "open_id",
    ) -> None:
        """Send an interactive card message."""
        token = await self._ensure_token()

        elements: list[dict[str, Any]] = [
            {
                "tag": "markdown",
                "content": content,
            }
        ]

        if buttons:
            actions = []
            for btn in buttons:
                actions.append({
                    "tag": "button",
                    "text": {"tag": "plain_text", "content": btn["text"]},
                    "type": "primary",
                    "value": {"action": btn.get("value", btn["text"])},
                })
            elements.append({"tag": "action", "actions": actions})

        card = {
            "header": {
                "title": {"tag": "plain_text", "content": title},
                "template": "blue",
            },
            "elements": elements,
        }

        payload = {
            "receive_id": recipient_id,
            "msg_type": "interactive",
            "content": json.dumps(card),
        }

        resp = await self._http.post(
            f"{API_BASE}/im/v1/messages",
            params={"receive_id_type": receive_id_type},
            headers={"Authorization": f"Bearer {token}"},
            json=payload,
        )
        resp.raise_for_status()

    # -- Reply in thread (reply to message_id) -------------------------------

    async def reply_message(self, message_id: str, text: str) -> None:
        """Reply to a specific message by message_id."""
        token = await self._ensure_token()

        payload = {
            "msg_type": "text",
            "content": json.dumps({"text": text}),
        }

        resp = await self._http.post(
            f"{API_BASE}/im/v1/messages/{message_id}/reply",
            headers={"Authorization": f"Bearer {token}"},
            json=payload,
        )
        resp.raise_for_status()

    # -- Event handling ------------------------------------------------------

    async def _handle_event(self, request: web.Request) -> web.Response:
        """Handle inbound Feishu event callbacks."""
        body = await request.json()

        # URL verification challenge
        if "challenge" in body:
            return web.json_response({"challenge": body["challenge"]})

        # Schema v2 event
        header = body.get("header", {})
        event = body.get("event", {})
        event_type = header.get("event_type", "")

        if event_type == "im.message.receive_v1":
            await self._handle_im_message(event)

        return web.Response(text="ok")

    async def _handle_im_message(self, event: dict) -> None:
        """Process an im.message.receive_v1 event."""
        message = event.get("message", {})
        sender = event.get("sender", {}).get("sender_id", {})
        msg_id = message.get("message_id", "")

        # Deduplicate
        if msg_id in self._seen_message_ids:
            return
        self._seen_message_ids.add(msg_id)
        # Keep set bounded
        if len(self._seen_message_ids) > 10000:
            self._seen_message_ids = set(list(self._seen_message_ids)[-5000:])

        msg_type = message.get("message_type", "")
        content_str = message.get("content", "{}")
        content = json.loads(content_str)

        parts: list[ContentPart] = []

        if msg_type == "text":
            parts.append(ContentPart(type=ContentType.TEXT, text=content.get("text", "")))
        elif msg_type == "image":
            parts.append(ContentPart(
                type=ContentType.IMAGE,
                url=content.get("image_key", ""),
            ))
        elif msg_type == "file":
            parts.append(ContentPart(
                type=ContentType.FILE,
                url=content.get("file_key", ""),
                filename=content.get("file_name", "file"),
            ))
        else:
            parts.append(ContentPart(
                type=ContentType.TEXT,
                text=f"[Unsupported: {msg_type}]",
            ))

        msg = Message(
            content=parts,
            sender_id=sender.get("open_id", ""),
            sender_name=sender.get("open_id", ""),
            session_id=message.get("chat_id", ""),
            metadata={
                "message_id": msg_id,
                "chat_type": message.get("chat_type", ""),
            },
        )

        reply = await self._process(msg)
        await self.reply_message(msg_id, reply)

    # -- Token management ----------------------------------------------------

    async def _refresh_token(self) -> None:
        """Fetch a new tenant_access_token."""
        if not self._http:
            raise RuntimeError("Channel not started")

        resp = await self._http.post(
            f"{API_BASE}/auth/v3/tenant_access_token/internal",
            json={
                "app_id": self._config.app_id,
                "app_secret": self._config.app_secret,
            },
        )
        resp.raise_for_status()
        data = resp.json()
        self._tenant_token = data["tenant_access_token"]
        self._token_expires = time.time() + data.get("expire", 7200) - 300

    async def _ensure_token(self) -> str:
        """Return a valid token, refreshing if necessary."""
        if time.time() >= self._token_expires:
            await self._refresh_token()
        return self._tenant_token
```

## Configuration

Environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `FEISHU_APP_ID` | Yes | App ID from Feishu Developer Console |
| `FEISHU_APP_SECRET` | Yes | App Secret |
| `FEISHU_VERIFICATION_TOKEN` | No | Event verification token (v1 events) |
| `FEISHU_ENCRYPT_KEY` | No | Event encryption key |
| `FEISHU_WEBHOOK_PORT` | No | Webhook listen port (default `9000`) |

`.env.example`:

```env
FEISHU_APP_ID=your-app-id
FEISHU_APP_SECRET=your-app-secret
FEISHU_VERIFICATION_TOKEN=
FEISHU_ENCRYPT_KEY=
FEISHU_WEBHOOK_PORT=9000
```

## Dependencies

```
httpx>=0.27
aiohttp>=3.9
```

## Usage

```python
import asyncio
import os
from {{PACKAGE_NAME}}.channels.feishu import FeishuChannel, FeishuConfig


async def handle_message(msg):
    """Replace with your agent logic."""
    return f"Echo: {msg.text}"


async def main():
    config = FeishuConfig(
        app_id=os.environ["FEISHU_APP_ID"],
        app_secret=os.environ["FEISHU_APP_SECRET"],
        verification_token=os.getenv("FEISHU_VERIFICATION_TOKEN", ""),
    )

    channel = FeishuChannel(config=config, process=handle_message)
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
