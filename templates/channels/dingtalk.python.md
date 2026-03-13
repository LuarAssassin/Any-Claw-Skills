# dingtalk.python.md

DingTalk channel adapter using the stream protocol. Supports stream client connection and card message responses.

## Generated File: `{{PACKAGE_NAME}}/channels/dingtalk.py`

```python
"""{{PROJECT_NAME}} - DingTalk channel adapter.

Connects to DingTalk via the Stream protocol (long-lived WebSocket).
Supports text messages, markdown replies, and interactive card messages.
"""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine, Optional

import httpx
from dingtalk_stream import (
    AckMessage,
    CallbackHandler,
    ChatbotHandler,
    ChatbotMessage,
    Credential,
    OpenDingTalkStreamClient,
)

logger = logging.getLogger(__name__)

API_BASE = "https://api.dingtalk.com"


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
    channel: str = "dingtalk"
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
# DingTalk adapter
# ---------------------------------------------------------------------------

@dataclass
class DingTalkConfig:
    app_key: str
    app_secret: str
    robot_code: str = ""               # For proactive messaging


class _MessageHandler(ChatbotHandler):
    """Internal handler bridging DingTalk stream events to the adapter."""

    def __init__(self, adapter: DingTalkChannel) -> None:
        super().__init__()
        self._adapter = adapter

    async def process(self, callback: CallbackHandler) -> AckMessage:
        incoming: ChatbotMessage = ChatbotMessage.from_dict(callback.data)

        parts: list[ContentPart] = []

        msg_type = incoming.message_type or "text"
        if msg_type == "text":
            text = (incoming.text or {}).get("content", "").strip()
            parts.append(ContentPart(type=ContentType.TEXT, text=text))
        elif msg_type == "richText":
            # Rich text may contain images and text segments
            for segment in (incoming.text or {}).get("richText", []):
                if "text" in segment:
                    parts.append(ContentPart(type=ContentType.TEXT, text=segment["text"]))
                if "downloadCode" in segment:
                    parts.append(ContentPart(
                        type=ContentType.IMAGE,
                        url=segment.get("downloadCode"),
                    ))
        elif msg_type == "picture":
            download_code = (incoming.text or {}).get("downloadCode", "")
            parts.append(ContentPart(type=ContentType.IMAGE, url=download_code))
        else:
            parts.append(ContentPart(
                type=ContentType.TEXT,
                text=f"[Unsupported message type: {msg_type}]",
            ))

        msg = Message(
            content=parts,
            sender_id=incoming.sender_id or "",
            sender_name=incoming.sender_nick or "",
            session_id=incoming.conversation_id or "",
            metadata={
                "conversation_type": incoming.conversation_type,
                "session_webhook": incoming.session_webhook,
                "sender_corp_id": incoming.sender_corp_id,
            },
        )

        loop = asyncio.get_event_loop()
        reply = await loop.run_in_executor(
            None, lambda: asyncio.run(self._adapter._process(msg))
        ) if not asyncio.get_event_loop().is_running() else await self._adapter._process(msg)

        # Reply via session webhook
        await self._adapter._reply_via_webhook(
            incoming.session_webhook, reply
        )

        return AckMessage.STATUS_OK, "OK"


class DingTalkChannel(ChannelAdapter):
    """DingTalk bot channel adapter using Stream protocol."""

    def __init__(self, config: DingTalkConfig, process: ProcessHandler) -> None:
        self._config = config
        self._process = process
        self._client: Optional[OpenDingTalkStreamClient] = None
        self._http: Optional[httpx.AsyncClient] = None

    # -- Lifecycle -----------------------------------------------------------

    async def start(self) -> None:
        self._http = httpx.AsyncClient(timeout=30.0)

        credential = Credential(self._config.app_key, self._config.app_secret)
        self._client = OpenDingTalkStreamClient(credential)

        handler = _MessageHandler(self)
        self._client.register_callback_handler(
            ChatbotHandler.TOPIC, handler
        )

        self._client.start()
        logger.info("DingTalk stream client started")

    async def stop(self) -> None:
        if self._http:
            await self._http.aclose()
        # The stream client runs in its own thread; it will be cleaned up on exit
        logger.info("DingTalk channel stopped")

    async def send_message(
        self,
        recipient_id: str,
        text: str,
        *,
        msg_type: str = "text",
        **kwargs: Any,
    ) -> None:
        """Send a proactive message using the robot API."""
        if not self._http:
            raise RuntimeError("Channel not started")

        token = await self._get_access_token()

        payload: dict[str, Any] = {
            "robotCode": self._config.robot_code,
            "userIds": [recipient_id],
            "msgKey": "sampleText" if msg_type == "text" else "sampleMarkdown",
            "msgParam": json.dumps({"content": text}),
        }

        resp = await self._http.post(
            f"{API_BASE}/v1.0/robot/oToMessages/batchSend",
            headers={"x-acs-dingtalk-access-token": token},
            json=payload,
        )
        resp.raise_for_status()

    # -- Reply via webhook ---------------------------------------------------

    async def _reply_via_webhook(self, webhook_url: str, text: str) -> None:
        """Reply to a message using the session webhook."""
        if not self._http or not webhook_url:
            return

        payload: dict[str, Any] = {
            "msgtype": "markdown",
            "markdown": {"title": "Reply", "text": text},
        }

        try:
            resp = await self._http.post(webhook_url, json=payload)
            resp.raise_for_status()
        except Exception:
            logger.warning("Failed to reply via DingTalk webhook", exc_info=True)

    # -- Card message --------------------------------------------------------

    async def send_card(
        self,
        webhook_url: str,
        title: str,
        text: str,
        buttons: Optional[list[dict[str, str]]] = None,
    ) -> None:
        """Send an interactive action card via session webhook."""
        if not self._http:
            raise RuntimeError("Channel not started")

        card: dict[str, Any] = {
            "msgtype": "actionCard",
            "actionCard": {
                "title": title,
                "text": text,
                "btnOrientation": "0",
            },
        }

        if buttons:
            card["actionCard"]["btns"] = [
                {"title": b["title"], "actionURL": b["url"]} for b in buttons
            ]

        resp = await self._http.post(webhook_url, json=card)
        resp.raise_for_status()

    # -- Access token --------------------------------------------------------

    async def _get_access_token(self) -> str:
        """Fetch an access token for the DingTalk API."""
        if not self._http:
            raise RuntimeError("Channel not started")

        resp = await self._http.post(
            f"{API_BASE}/v1.0/oauth2/accessToken",
            json={
                "appKey": self._config.app_key,
                "appSecret": self._config.app_secret,
            },
        )
        resp.raise_for_status()
        return resp.json()["accessToken"]
```

## Configuration

Environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `DINGTALK_APP_KEY` | Yes | App Key from DingTalk Developer Console |
| `DINGTALK_APP_SECRET` | Yes | App Secret |
| `DINGTALK_ROBOT_CODE` | No | Robot code for proactive messages |

`.env.example`:

```env
DINGTALK_APP_KEY=your-app-key
DINGTALK_APP_SECRET=your-app-secret
DINGTALK_ROBOT_CODE=
```

## Dependencies

```
dingtalk-stream>=1.4
httpx>=0.27
```

## Usage

```python
import asyncio
import os
from {{PACKAGE_NAME}}.channels.dingtalk import DingTalkChannel, DingTalkConfig


async def handle_message(msg):
    """Replace with your agent logic."""
    return f"Echo: {msg.text}"


async def main():
    config = DingTalkConfig(
        app_key=os.environ["DINGTALK_APP_KEY"],
        app_secret=os.environ["DINGTALK_APP_SECRET"],
        robot_code=os.getenv("DINGTALK_ROBOT_CODE", ""),
    )

    channel = DingTalkChannel(config=config, process=handle_message)
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
