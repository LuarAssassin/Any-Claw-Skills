# discord.python.md

Discord channel adapter using `discord.py`. Supports event-based message handling, slash commands, and embed responses.

## Generated File: `{{PACKAGE_NAME}}/channels/discord_.py`

```python
"""{{PROJECT_NAME}} - Discord channel adapter.

Connects to Discord via discord.py gateway.
Supports text messages, slash commands, and rich embed responses.
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine, Optional

import discord
from discord import app_commands

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
    channel: str = "discord"
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
# Discord adapter
# ---------------------------------------------------------------------------

@dataclass
class DiscordConfig:
    bot_token: str
    guild_id: Optional[int] = None           # If set, slash commands sync to this guild only
    allowed_channel_ids: list[int] = field(default_factory=list)  # Empty = all channels
    require_mention: bool = False             # If True, only respond when @mentioned


class _AssistantClient(discord.Client):
    """Internal discord.Client subclass with command tree."""

    def __init__(
        self,
        config: DiscordConfig,
        process: ProcessHandler,
        *,
        intents: discord.Intents,
    ) -> None:
        super().__init__(intents=intents)
        self.config = config
        self.process = process
        self.tree = app_commands.CommandTree(self)

        @self.tree.command(name="ask", description="Ask the assistant a question")
        @app_commands.describe(question="Your question")
        async def ask_command(interaction: discord.Interaction, question: str) -> None:
            await interaction.response.defer(thinking=True)

            msg = Message(
                content=[ContentPart(type=ContentType.TEXT, text=question)],
                sender_id=str(interaction.user.id),
                sender_name=interaction.user.display_name,
                session_id=str(interaction.channel_id),
                metadata={"slash_command": "ask"},
            )

            reply = await self.process(msg)
            embed = discord.Embed(description=reply, color=0x5865F2)
            embed.set_footer(text=f"Asked by {interaction.user.display_name}")
            await interaction.followup.send(embed=embed)

    async def setup_hook(self) -> None:
        if self.config.guild_id:
            guild = discord.Object(id=self.config.guild_id)
            self.tree.copy_global_to(guild=guild)
            await self.tree.sync(guild=guild)
        else:
            await self.tree.sync()
        logger.info("Slash commands synced")


class DiscordChannel(ChannelAdapter):
    """Discord bot channel adapter."""

    def __init__(self, config: DiscordConfig, process: ProcessHandler) -> None:
        self._config = config
        self._process = process
        self._client: Optional[_AssistantClient] = None
        self._task: Optional[asyncio.Task[None]] = None

    # -- Lifecycle -----------------------------------------------------------

    async def start(self) -> None:
        intents = discord.Intents.default()
        intents.message_content = True

        self._client = _AssistantClient(
            self._config, self._process, intents=intents
        )

        @self._client.event
        async def on_ready() -> None:
            logger.info("Discord bot connected as %s", self._client.user)

        @self._client.event
        async def on_message(message: discord.Message) -> None:
            await self._handle_message(message)

        self._task = asyncio.create_task(self._client.start(self._config.bot_token))
        logger.info("Discord channel starting")

    async def stop(self) -> None:
        if self._client:
            await self._client.close()
        if self._task:
            self._task.cancel()
        logger.info("Discord channel stopped")

    async def send_message(
        self,
        recipient_id: str,
        text: str,
        *,
        embed: bool = False,
        **kwargs: Any,
    ) -> None:
        """Send a message to a Discord channel by ID."""
        if not self._client:
            raise RuntimeError("Channel not started")

        channel = self._client.get_channel(int(recipient_id))
        if not channel or not isinstance(channel, discord.abc.Messageable):
            raise ValueError(f"Channel {recipient_id} not found or not messageable")

        if embed:
            await channel.send(embed=discord.Embed(description=text, color=0x5865F2))
        else:
            await channel.send(text)

    # -- Message handling ----------------------------------------------------

    def _is_allowed_channel(self, channel_id: int) -> bool:
        if not self._config.allowed_channel_ids:
            return True
        return channel_id in self._config.allowed_channel_ids

    async def _handle_message(self, message: discord.Message) -> None:
        # Ignore own messages
        if message.author == self._client.user:
            return

        # Ignore bots
        if message.author.bot:
            return

        # Channel filter
        if not self._is_allowed_channel(message.channel.id):
            return

        # Mention filter
        if self._config.require_mention:
            if self._client.user not in message.mentions:
                return

        # Build content parts
        parts: list[ContentPart] = []

        text = message.content
        # Strip bot mention from text
        if self._client.user:
            text = text.replace(f"<@{self._client.user.id}>", "").strip()

        if text:
            parts.append(ContentPart(type=ContentType.TEXT, text=text))

        for attachment in message.attachments:
            if attachment.content_type and attachment.content_type.startswith("image/"):
                parts.append(
                    ContentPart(
                        type=ContentType.IMAGE,
                        url=attachment.url,
                        mime_type=attachment.content_type,
                        filename=attachment.filename,
                    )
                )
            else:
                parts.append(
                    ContentPart(
                        type=ContentType.FILE,
                        url=attachment.url,
                        mime_type=attachment.content_type or "application/octet-stream",
                        filename=attachment.filename,
                    )
                )

        if not parts:
            return

        msg = Message(
            content=parts,
            sender_id=str(message.author.id),
            sender_name=message.author.display_name,
            session_id=str(message.channel.id),
            metadata={
                "guild_id": str(message.guild.id) if message.guild else None,
                "is_dm": isinstance(message.channel, discord.DMChannel),
            },
        )

        reply = await self._process(msg)

        # Split long replies (Discord limit: 2000 chars)
        chunks = [reply[i : i + 2000] for i in range(0, len(reply), 2000)]
        for chunk in chunks:
            await message.reply(chunk, mention_author=False)
```

## Configuration

Environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `DISCORD_BOT_TOKEN` | Yes | Bot token from Discord Developer Portal |
| `DISCORD_GUILD_ID` | No | Guild ID for guild-specific slash commands |
| `DISCORD_ALLOWED_CHANNELS` | No | Comma-separated channel IDs |
| `DISCORD_REQUIRE_MENTION` | No | `true` to require @mention in servers |

`.env.example`:

```env
DISCORD_BOT_TOKEN=your-bot-token
DISCORD_GUILD_ID=
DISCORD_ALLOWED_CHANNELS=
DISCORD_REQUIRE_MENTION=false
```

## Dependencies

```
discord.py>=2.3
```

## Usage

```python
import asyncio
import os
from {{PACKAGE_NAME}}.channels.discord_ import DiscordChannel, DiscordConfig


async def handle_message(msg):
    """Replace with your agent logic."""
    return f"Echo: {msg.text}"


async def main():
    config = DiscordConfig(
        bot_token=os.environ["DISCORD_BOT_TOKEN"],
        guild_id=int(gid) if (gid := os.getenv("DISCORD_GUILD_ID")) else None,
        require_mention=os.getenv("DISCORD_REQUIRE_MENTION", "").lower() == "true",
    )

    channel = DiscordChannel(config=config, process=handle_message)
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
