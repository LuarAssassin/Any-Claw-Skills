# cli.python.md

CLI/REPL channel adapter using the `rich` library. Provides a rich terminal interface with streaming response display and command history.

## Generated File: `{{PACKAGE_NAME}}/channels/cli.py`

```python
"""{{PROJECT_NAME}} - CLI/REPL channel adapter.

Interactive terminal interface using the Rich library.
Supports streaming response display, command history, and multiline input.
"""

from __future__ import annotations

import asyncio
import logging
import os
import readline
import signal
import sys
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine, Optional

from rich.console import Console
from rich.live import Live
from rich.markdown import Markdown
from rich.panel import Panel
from rich.text import Text

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
    channel: str = "cli"
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
# CLI adapter
# ---------------------------------------------------------------------------

HISTORY_FILE = os.path.expanduser("~/.{{PACKAGE_NAME}}_history")

BUILTIN_COMMANDS: dict[str, str] = {
    "/help": "Show available commands",
    "/clear": "Clear the screen",
    "/history": "Show conversation history",
    "/quit": "Exit the assistant",
}


@dataclass
class CLIConfig:
    prompt: str = "> "
    assistant_name: str = "{{PROJECT_NAME}}"
    show_markdown: bool = True         # Render responses as markdown
    history_file: str = HISTORY_FILE
    max_display_history: int = 20


class CLIChannel(ChannelAdapter):
    """CLI/REPL channel adapter with rich terminal output."""

    def __init__(self, config: CLIConfig, process: ProcessHandler) -> None:
        self._config = config
        self._process = process
        self._console = Console()
        self._running = False
        self._conversation: list[tuple[str, str]] = []  # (role, text)

    # -- Lifecycle -----------------------------------------------------------

    async def start(self) -> None:
        self._running = True
        self._load_history()
        self._print_banner()
        await self._repl_loop()

    async def stop(self) -> None:
        self._running = False
        self._save_history()
        self._console.print("\n[dim]Goodbye.[/dim]")

    async def send_message(
        self, recipient_id: str, text: str, **kwargs: Any
    ) -> None:
        """Display a message in the terminal (used for proactive messages)."""
        self._display_response(text)

    # -- REPL loop -----------------------------------------------------------

    async def _repl_loop(self) -> None:
        """Main read-eval-print loop."""
        loop = asyncio.get_event_loop()

        while self._running:
            try:
                user_input = await loop.run_in_executor(None, self._read_input)
            except (EOFError, KeyboardInterrupt):
                await self.stop()
                break

            if not user_input:
                continue

            # Handle built-in commands
            if user_input.startswith("/"):
                handled = self._handle_command(user_input)
                if handled:
                    continue

            # Build message
            msg = Message(
                content=[ContentPart(type=ContentType.TEXT, text=user_input)],
                sender_id="local",
                sender_name=os.getenv("USER", "user"),
                session_id="cli",
            )

            self._conversation.append(("user", user_input))

            # Process with spinner
            with self._console.status("[bold]Thinking...", spinner="dots"):
                try:
                    reply = await self._process(msg)
                except Exception as exc:
                    reply = f"[Error] {exc}"
                    logger.error("Process error", exc_info=True)

            self._conversation.append(("assistant", reply))
            self._display_response(reply)

    # -- Input ---------------------------------------------------------------

    def _read_input(self) -> str:
        """Read a line of input from the user. Supports readline editing."""
        try:
            return input(self._config.prompt).strip()
        except EOFError:
            raise

    # -- Output --------------------------------------------------------------

    def _display_response(self, text: str) -> None:
        """Render the assistant's response."""
        self._console.print()
        if self._config.show_markdown:
            self._console.print(
                Panel(
                    Markdown(text),
                    title=self._config.assistant_name,
                    border_style="blue",
                    padding=(1, 2),
                )
            )
        else:
            self._console.print(
                Panel(
                    text,
                    title=self._config.assistant_name,
                    border_style="blue",
                    padding=(1, 2),
                )
            )
        self._console.print()

    def _print_banner(self) -> None:
        """Print the welcome banner."""
        self._console.print()
        self._console.print(
            Panel(
                Text.from_markup(
                    f"[bold]{self._config.assistant_name}[/bold]\n"
                    f"[dim]Type /help for commands, /quit to exit.[/dim]"
                ),
                border_style="green",
            )
        )
        self._console.print()

    # -- Built-in commands ---------------------------------------------------

    def _handle_command(self, cmd: str) -> bool:
        """Handle a built-in slash command. Returns True if handled."""
        cmd_lower = cmd.lower().strip()

        if cmd_lower == "/quit" or cmd_lower == "/exit":
            self._running = False
            return True

        if cmd_lower == "/clear":
            self._console.clear()
            self._print_banner()
            return True

        if cmd_lower == "/help":
            self._console.print("\n[bold]Available commands:[/bold]")
            for name, desc in BUILTIN_COMMANDS.items():
                self._console.print(f"  [cyan]{name:<12}[/cyan] {desc}")
            self._console.print()
            return True

        if cmd_lower == "/history":
            if not self._conversation:
                self._console.print("[dim]No conversation history.[/dim]")
                return True

            recent = self._conversation[-self._config.max_display_history :]
            self._console.print(f"\n[bold]Last {len(recent)} messages:[/bold]\n")
            for role, text in recent:
                color = "green" if role == "user" else "blue"
                label = "You" if role == "user" else self._config.assistant_name
                preview = text[:120] + ("..." if len(text) > 120 else "")
                self._console.print(f"  [{color}]{label}:[/{color}] {preview}")
            self._console.print()
            return True

        return False

    # -- Readline history ----------------------------------------------------

    def _load_history(self) -> None:
        """Load readline history from file."""
        try:
            if os.path.exists(self._config.history_file):
                readline.read_history_file(self._config.history_file)
        except OSError:
            pass

    def _save_history(self) -> None:
        """Save readline history to file."""
        try:
            readline.set_history_length(1000)
            readline.write_history_file(self._config.history_file)
        except OSError:
            pass
```

## Configuration

Environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `CLI_PROMPT` | No | Input prompt string (default `> `) |
| `CLI_SHOW_MARKDOWN` | No | `true` (default) to render markdown |

`.env.example`:

```env
CLI_PROMPT=>
CLI_SHOW_MARKDOWN=true
```

## Dependencies

```
rich>=13.0
```

## Usage

```python
import asyncio
from {{PACKAGE_NAME}}.channels.cli import CLIChannel, CLIConfig


async def handle_message(msg):
    """Replace with your agent logic."""
    return f"Echo: {msg.text}"


async def main():
    config = CLIConfig(
        assistant_name="{{PROJECT_NAME}}",
        show_markdown=True,
    )

    channel = CLIChannel(config=config, process=handle_message)

    try:
        await channel.start()
    except KeyboardInterrupt:
        await channel.stop()


if __name__ == "__main__":
    asyncio.run(main())
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Project display name |
| `{{PACKAGE_NAME}}` | Python package name (e.g. `my_assistant`) |
