# whatsapp.python.md

WhatsApp channel adapter using the Meta Cloud API. Supports webhook verification, text/media messages, and message status tracking.

## Generated File: `{{PACKAGE_NAME}}/channels/whatsapp.py`

```python
"""{{PROJECT_NAME}} - WhatsApp channel adapter.

Connects to WhatsApp via Meta Cloud API.
Implements webhook verification, inbound message handling, and outbound replies.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine, Optional

import httpx
from aiohttp import web

logger = logging.getLogger(__name__)

API_BASE = "https://graph.facebook.com/v21.0"


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
    channel: str = "whatsapp"
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
# WhatsApp adapter
# ---------------------------------------------------------------------------

@dataclass
class WhatsAppConfig:
    access_token: str
    phone_number_id: str
    verify_token: str                  # Token for webhook verification handshake
    app_secret: str = ""               # For payload signature verification
    webhook_port: int = 8080
    webhook_path: str = "/webhook"


class WhatsAppChannel(ChannelAdapter):
    """WhatsApp Cloud API channel adapter."""

    def __init__(self, config: WhatsAppConfig, process: ProcessHandler) -> None:
        self._config = config
        self._process = process
        self._http: Optional[httpx.AsyncClient] = None
        self._runner: Optional[web.AppRunner] = None
        self._site: Optional[web.TCPSite] = None

    # -- Lifecycle -----------------------------------------------------------

    async def start(self) -> None:
        self._http = httpx.AsyncClient(
            base_url=API_BASE,
            headers={"Authorization": f"Bearer {self._config.access_token}"},
            timeout=30.0,
        )

        app = web.Application()
        app.router.add_get(self._config.webhook_path, self._verify_webhook)
        app.router.add_post(self._config.webhook_path, self._handle_webhook)

        self._runner = web.AppRunner(app)
        await self._runner.setup()
        self._site = web.TCPSite(self._runner, "0.0.0.0", self._config.webhook_port)
        await self._site.start()
        logger.info(
            "WhatsApp webhook listening on port %d%s",
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
        logger.info("WhatsApp channel stopped")

    async def send_message(
        self,
        recipient_id: str,
        text: str,
        *,
        reply_to_message_id: Optional[str] = None,
        **kwargs: Any,
    ) -> None:
        """Send a text message to a WhatsApp user."""
        if not self._http:
            raise RuntimeError("Channel not started")

        payload: dict[str, Any] = {
            "messaging_product": "whatsapp",
            "to": recipient_id,
            "type": "text",
            "text": {"body": text},
        }
        if reply_to_message_id:
            payload["context"] = {"message_id": reply_to_message_id}

        resp = await self._http.post(
            f"/{self._config.phone_number_id}/messages", json=payload
        )
        resp.raise_for_status()

    # -- Mark as read --------------------------------------------------------

    async def _mark_read(self, message_id: str) -> None:
        """Mark an inbound message as read."""
        if not self._http:
            return
        try:
            await self._http.post(
                f"/{self._config.phone_number_id}/messages",
                json={
                    "messaging_product": "whatsapp",
                    "status": "read",
                    "message_id": message_id,
                },
            )
        except Exception:
            logger.debug("Failed to mark message %s as read", message_id, exc_info=True)

    # -- Media download ------------------------------------------------------

    async def _download_media(self, media_id: str) -> tuple[bytes, str]:
        """Download media by ID. Returns (data, mime_type)."""
        if not self._http:
            raise RuntimeError("Channel not started")

        # Step 1: get media URL
        meta_resp = await self._http.get(f"/{media_id}")
        meta_resp.raise_for_status()
        meta = meta_resp.json()
        media_url = meta["url"]
        mime_type = meta.get("mime_type", "application/octet-stream")

        # Step 2: download binary
        data_resp = await self._http.get(media_url)
        data_resp.raise_for_status()
        return data_resp.content, mime_type

    # -- Webhook handlers ----------------------------------------------------

    async def _verify_webhook(self, request: web.Request) -> web.Response:
        """Handle GET verification challenge from Meta."""
        mode = request.query.get("hub.mode")
        token = request.query.get("hub.verify_token")
        challenge = request.query.get("hub.challenge")

        if mode == "subscribe" and token == self._config.verify_token:
            logger.info("Webhook verified")
            return web.Response(text=challenge or "")
        return web.Response(status=403, text="Forbidden")

    def _verify_signature(self, body: bytes, signature: str) -> bool:
        """Verify X-Hub-Signature-256 header."""
        if not self._config.app_secret:
            return True  # Skip if secret not configured
        expected = hmac.new(
            self._config.app_secret.encode(), body, hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(f"sha256={expected}", signature)

    async def _handle_webhook(self, request: web.Request) -> web.Response:
        """Handle POST webhook events from Meta."""
        body = await request.read()

        # Signature verification
        signature = request.headers.get("X-Hub-Signature-256", "")
        if not self._verify_signature(body, signature):
            return web.Response(status=403, text="Invalid signature")

        payload = await request.json()

        for entry in payload.get("entry", []):
            for change in entry.get("changes", []):
                value = change.get("value", {})

                # Handle status updates
                for status in value.get("statuses", []):
                    logger.debug(
                        "Message %s status: %s",
                        status.get("id"),
                        status.get("status"),
                    )

                # Handle inbound messages
                for wa_msg in value.get("messages", []):
                    await self._process_inbound(wa_msg, value.get("contacts", []))

        return web.Response(text="OK")

    async def _process_inbound(
        self, wa_msg: dict, contacts: list[dict]
    ) -> None:
        """Convert a WhatsApp inbound message and dispatch to processor."""
        msg_type = wa_msg.get("type", "")
        sender = wa_msg.get("from", "")
        msg_id = wa_msg.get("id", "")

        # Resolve sender name from contacts
        sender_name = sender
        for contact in contacts:
            if contact.get("wa_id") == sender:
                sender_name = contact.get("profile", {}).get("name", sender)
                break

        parts: list[ContentPart] = []

        if msg_type == "text":
            parts.append(
                ContentPart(type=ContentType.TEXT, text=wa_msg["text"]["body"])
            )
        elif msg_type == "image":
            media = wa_msg.get("image", {})
            data, mime = await self._download_media(media["id"])
            parts.append(
                ContentPart(type=ContentType.IMAGE, data=data, mime_type=mime)
            )
            if caption := media.get("caption"):
                parts.insert(0, ContentPart(type=ContentType.TEXT, text=caption))
        elif msg_type == "document":
            media = wa_msg.get("document", {})
            data, mime = await self._download_media(media["id"])
            parts.append(ContentPart(
                type=ContentType.FILE,
                data=data,
                mime_type=mime,
                filename=media.get("filename"),
            ))
        else:
            logger.debug("Unsupported message type: %s", msg_type)
            return

        msg = Message(
            content=parts,
            sender_id=sender,
            sender_name=sender_name,
            session_id=sender,  # WhatsApp: session = per-user
            metadata={"message_id": msg_id, "type": msg_type},
        )

        # Mark as read
        await self._mark_read(msg_id)

        reply = await self._process(msg)
        await self.send_message(sender, reply, reply_to_message_id=msg_id)
```

## Configuration

Environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `WHATSAPP_ACCESS_TOKEN` | Yes | Permanent or temporary access token |
| `WHATSAPP_PHONE_NUMBER_ID` | Yes | Phone Number ID from Meta dashboard |
| `WHATSAPP_VERIFY_TOKEN` | Yes | Token you set for webhook verification |
| `WHATSAPP_APP_SECRET` | No | App secret for signature verification |
| `WHATSAPP_WEBHOOK_PORT` | No | Webhook listen port (default `8080`) |

`.env.example`:

```env
WHATSAPP_ACCESS_TOKEN=your-access-token
WHATSAPP_PHONE_NUMBER_ID=123456789
WHATSAPP_VERIFY_TOKEN=my-verify-token
WHATSAPP_APP_SECRET=
WHATSAPP_WEBHOOK_PORT=8080
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
from {{PACKAGE_NAME}}.channels.whatsapp import WhatsAppChannel, WhatsAppConfig


async def handle_message(msg):
    """Replace with your agent logic."""
    return f"Echo: {msg.text}"


async def main():
    config = WhatsAppConfig(
        access_token=os.environ["WHATSAPP_ACCESS_TOKEN"],
        phone_number_id=os.environ["WHATSAPP_PHONE_NUMBER_ID"],
        verify_token=os.environ["WHATSAPP_VERIFY_TOKEN"],
        app_secret=os.getenv("WHATSAPP_APP_SECRET", ""),
    )

    channel = WhatsAppChannel(config=config, process=handle_message)
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
