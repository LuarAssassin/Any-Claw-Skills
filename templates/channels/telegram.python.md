# telegram.python.md

Telegram channel adapter using the `python-telegram-bot` library. Supports polling and webhook modes, text/photo/document handling, and reply keyboards.

## Generated File: `{{PACKAGE_NAME}}/channels/telegram.py`

```python
"""{{PROJECT_NAME}} - Telegram channel adapter.

Connects to Telegram Bot API via python-telegram-bot.
Supports polling mode (development) and webhook mode (production).
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine, Optional

from telegram import (
    Bot,
    Document,
    PhotoSize,
    ReplyKeyboardMarkup,
    ReplyKeyboardRemove,
    Update,
)
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

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
    channel: str = "telegram"
    session_id: str = ""
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def text(self) -> str:
        parts = [p.text for p in self.content if p.type == ContentType.TEXT and p.text]
        return "\n".join(parts)


# Callback type: receives a Message, returns response text.
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
# Telegram adapter
# ---------------------------------------------------------------------------

@dataclass
class TelegramConfig:
    bot_token: str
    mode: str = "polling"          # "polling" or "webhook"
    webhook_url: str = ""          # Required when mode == "webhook"
    webhook_port: int = 8443
    allowed_user_ids: list[str] = field(default_factory=list)  # Empty = allow all


class TelegramChannel(ChannelAdapter):
    """Telegram bot channel adapter."""

    def __init__(self, config: TelegramConfig, process: ProcessHandler) -> None:
        self._config = config
        self._process = process
        self._app: Optional[Application] = None

    # -- Lifecycle -----------------------------------------------------------

    async def start(self) -> None:
        builder = Application.builder().token(self._config.bot_token)
        self._app = builder.build()

        self._app.add_handler(CommandHandler("start", self._handle_start))
        self._app.add_handler(
            MessageHandler(filters.TEXT & ~filters.COMMAND, self._handle_text)
        )
        self._app.add_handler(MessageHandler(filters.PHOTO, self._handle_photo))
        self._app.add_handler(MessageHandler(filters.Document.ALL, self._handle_document))

        await self._app.initialize()
        await self._app.start()

        if self._config.mode == "webhook":
            await self._app.updater.start_webhook(
                listen="0.0.0.0",
                port=self._config.webhook_port,
                url_path=self._config.bot_token,
                webhook_url=f"{self._config.webhook_url}/{self._config.bot_token}",
            )
            logger.info("Telegram webhook started on port %d", self._config.webhook_port)
        else:
            await self._app.updater.start_polling(drop_pending_updates=True)
            logger.info("Telegram polling started")

    async def stop(self) -> None:
        if self._app:
            await self._app.updater.stop()
            await self._app.stop()
            await self._app.shutdown()
            logger.info("Telegram channel stopped")

    async def send_message(
        self,
        recipient_id: str,
        text: str,
        *,
        reply_keyboard: Optional[list[list[str]]] = None,
        **kwargs: Any,
    ) -> None:
        """Send a text message, optionally with a reply keyboard."""
        if not self._app:
            raise RuntimeError("Channel not started")

        markup: Any = ReplyKeyboardRemove()
        if reply_keyboard:
            markup = ReplyKeyboardMarkup(
                reply_keyboard, one_time_keyboard=True, resize_keyboard=True
            )

        await self._app.bot.send_message(
            chat_id=int(recipient_id), text=text, reply_markup=markup
        )

    # -- Access control ------------------------------------------------------

    def _is_allowed(self, user_id: int) -> bool:
        if not self._config.allowed_user_ids:
            return True
        return str(user_id) in self._config.allowed_user_ids

    # -- Handlers ------------------------------------------------------------

    async def _handle_start(
        self, update: Update, context: ContextTypes.DEFAULT_TYPE
    ) -> None:
        if update.effective_user and not self._is_allowed(update.effective_user.id):
            return
        await update.message.reply_text(
            "Hello! I am your assistant. Send me a message to get started."
        )

    async def _handle_text(
        self, update: Update, context: ContextTypes.DEFAULT_TYPE
    ) -> None:
        user = update.effective_user
        if not user or not self._is_allowed(user.id):
            return

        msg = Message(
            content=[ContentPart(type=ContentType.TEXT, text=update.message.text)],
            sender_id=str(user.id),
            sender_name=user.full_name or str(user.id),
            session_id=str(update.effective_chat.id),
            metadata={"chat_type": update.effective_chat.type},
        )

        reply = await self._process(msg)
        await update.message.reply_text(reply)

    async def _handle_photo(
        self, update: Update, context: ContextTypes.DEFAULT_TYPE
    ) -> None:
        user = update.effective_user
        if not user or not self._is_allowed(user.id):
            return

        photo: PhotoSize = update.message.photo[-1]  # highest resolution
        file = await context.bot.get_file(photo.file_id)
        photo_bytes = await file.download_as_bytearray()

        parts: list[ContentPart] = [
            ContentPart(
                type=ContentType.IMAGE,
                data=bytes(photo_bytes),
                mime_type="image/jpeg",
            ),
        ]
        if update.message.caption:
            parts.insert(
                0, ContentPart(type=ContentType.TEXT, text=update.message.caption)
            )

        msg = Message(
            content=parts,
            sender_id=str(user.id),
            sender_name=user.full_name or str(user.id),
            session_id=str(update.effective_chat.id),
        )

        reply = await self._process(msg)
        await update.message.reply_text(reply)

    async def _handle_document(
        self, update: Update, context: ContextTypes.DEFAULT_TYPE
    ) -> None:
        user = update.effective_user
        if not user or not self._is_allowed(user.id):
            return

        doc: Document = update.message.document
        file = await context.bot.get_file(doc.file_id)
        doc_bytes = await file.download_as_bytearray()

        parts: list[ContentPart] = [
            ContentPart(
                type=ContentType.FILE,
                data=bytes(doc_bytes),
                filename=doc.file_name or "file",
                mime_type=doc.mime_type or "application/octet-stream",
            ),
        ]
        if update.message.caption:
            parts.insert(
                0, ContentPart(type=ContentType.TEXT, text=update.message.caption)
            )

        msg = Message(
            content=parts,
            sender_id=str(user.id),
            sender_name=user.full_name or str(user.id),
            session_id=str(update.effective_chat.id),
        )

        reply = await self._process(msg)
        await update.message.reply_text(reply)
```

## Configuration

Environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Yes | Bot token from @BotFather |
| `TELEGRAM_MODE` | No | `polling` (default) or `webhook` |
| `TELEGRAM_WEBHOOK_URL` | If webhook | Public HTTPS URL for webhook |
| `TELEGRAM_WEBHOOK_PORT` | No | Webhook listen port (default `8443`) |
| `TELEGRAM_ALLOWED_USERS` | No | Comma-separated user IDs for access control |

`.env.example`:

```env
TELEGRAM_BOT_TOKEN=123456:ABC-DEF
TELEGRAM_MODE=polling
TELEGRAM_WEBHOOK_URL=https://example.com
TELEGRAM_WEBHOOK_PORT=8443
TELEGRAM_ALLOWED_USERS=
```

## Dependencies

```
python-telegram-bot>=21.0
```

## Usage

```python
import asyncio
import os
from {{PACKAGE_NAME}}.channels.telegram import TelegramChannel, TelegramConfig


async def handle_message(msg):
    """Replace with your agent logic."""
    return f"Echo: {msg.text}"


async def main():
    config = TelegramConfig(
        bot_token=os.environ["TELEGRAM_BOT_TOKEN"],
        mode=os.getenv("TELEGRAM_MODE", "polling"),
        webhook_url=os.getenv("TELEGRAM_WEBHOOK_URL", ""),
    )

    channel = TelegramChannel(config=config, process=handle_message)
    await channel.start()

    try:
        await asyncio.Event().wait()  # Run until interrupted
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
