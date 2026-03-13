# config.py.md

Template for the Standard/Python tier scaffold.

## Generated File: `config.py`

```python
"""{{PROJECT_NAME}} configuration.

Uses pydantic-settings to load values from environment variables and an
optional `.env` file.  Configuration is split into logical sections:
provider (LLM), channels (inbound/outbound), and domain-specific settings.
"""

from __future__ import annotations

import logging
from enum import Enum
from pathlib import Path
from typing import Annotated

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class LogLevel(str, Enum):
    """Supported log levels."""

    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class ProviderKind(str, Enum):
    """Supported LLM provider backends."""

    OPENAI = "openai"
    ANTHROPIC = "anthropic"
    CUSTOM = "custom"


# ---------------------------------------------------------------------------
# Settings model
# ---------------------------------------------------------------------------

class Settings(BaseSettings):
    """Root configuration for {{PROJECT_NAME}}.

    Values are read from environment variables (case-insensitive) and from a
    `.env` file if present in the working directory.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        env_prefix="{{ENV_PREFIX}}_",
        case_sensitive=False,
        extra="ignore",
    )

    # -- General --------------------------------------------------------------

    app_name: str = "{{PROJECT_NAME}}"
    log_level: LogLevel = LogLevel.INFO
    debug: bool = False
    data_dir: Path = Field(
        default=Path("./data"),
        description="Directory for persistent data and caches.",
    )

    # -- Provider (LLM) -------------------------------------------------------

    provider_kind: ProviderKind = ProviderKind.{{DEFAULT_PROVIDER_KIND}}
    provider_base_url: str = "{{DEFAULT_PROVIDER_URL}}"
    provider_api_key: SecretStr = SecretStr("")
    provider_model: str = "{{DEFAULT_MODEL}}"
    provider_temperature: Annotated[float, Field(ge=0.0, le=2.0)] = 0.7
    provider_timeout: float = Field(
        default=60.0,
        description="HTTP timeout in seconds for LLM requests.",
    )
    provider_max_retries: int = Field(default=3, ge=0)

    # -- Channels --------------------------------------------------------------

    enabled_channels: list[str] = Field(
        default_factory=lambda: ["cli"],
        description=(
            "List of channel adapters to activate at startup. "
            "Each name must match a registered ChannelAdapter."
        ),
    )

    # Channel-specific credentials (add more as needed)
    discord_token: SecretStr = SecretStr("")
    slack_bot_token: SecretStr = SecretStr("")
    webhook_secret: SecretStr = SecretStr("")

    # -- Domain ----------------------------------------------------------------

    max_history_turns: int = Field(
        default=20,
        ge=1,
        description="Maximum conversation turns to keep in context.",
    )
    system_prompt_path: Path | None = Field(
        default=None,
        description="Optional path to a custom system-prompt file.",
    )

    # -- Validators ------------------------------------------------------------

    @field_validator("data_dir", mode="after")
    @classmethod
    def _ensure_data_dir(cls, v: Path) -> Path:
        v.mkdir(parents=True, exist_ok=True)
        return v

    @field_validator("system_prompt_path", mode="after")
    @classmethod
    def _check_prompt_file(cls, v: Path | None) -> Path | None:
        if v is not None and not v.is_file():
            logger.warning("system_prompt_path does not exist: %s", v)
        return v

    # -- Helpers ---------------------------------------------------------------

    def get_provider_api_key(self) -> str:
        """Return the provider API key as a plain string."""
        return self.provider_api_key.get_secret_value()

    def load_system_prompt(self) -> str | None:
        """Read the system prompt from disk, if configured."""
        if self.system_prompt_path and self.system_prompt_path.is_file():
            return self.system_prompt_path.read_text(encoding="utf-8").strip()
        return None

    def summary(self) -> dict[str, object]:
        """Return a safe (no secrets) summary for logging."""
        return {
            "app_name": self.app_name,
            "log_level": self.log_level.value,
            "provider_kind": self.provider_kind.value,
            "provider_model": self.provider_model,
            "enabled_channels": self.enabled_channels,
            "max_history_turns": self.max_history_turns,
            "debug": self.debug,
        }
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Human-readable project name |
| `{{ENV_PREFIX}}` | Environment-variable prefix, uppercase (e.g. `MYAPP` yields `MYAPP_LOG_LEVEL`) |
| `{{DEFAULT_PROVIDER_KIND}}` | Default enum variant for the LLM provider (`OPENAI`, `ANTHROPIC`, or `CUSTOM`) |
| `{{DEFAULT_PROVIDER_URL}}` | Default base URL for the LLM API (e.g. `https://api.openai.com/v1`) |
| `{{DEFAULT_MODEL}}` | Default model identifier (e.g. `gpt-4o`) |
