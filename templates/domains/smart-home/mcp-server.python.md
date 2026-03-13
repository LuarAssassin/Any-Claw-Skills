# Smart Home MCP Server (Python)

Model Context Protocol server for smart home tools using [FastMCP](https://github.com/jlowin/fastmcp).

## Dependencies

```
fastmcp>=2.0
pydantic>=2.0
aiohttp>=3.9
```

## Generated File: `mcp_servers/smart_home_server.py`

```python
"""Smart home MCP server for {{PROJECT_NAME}}."""

import os
from typing import Any

from fastmcp import FastMCP

from tools.smart_home import (
    DeviceState,
    EnergyReport,
    Rule,
    Scene,
    SmartHomeHub,
    device_control,
    automation_rules,
    energy_monitor,
    scene_manager,
)

mcp = FastMCP(
    "{{PROJECT_NAME}} Smart Home",
    description="Control smart home devices, automations, energy monitoring, and scenes.",
)


# ---------------------------------------------------------------------------
# Device control
# ---------------------------------------------------------------------------

@mcp.tool()
async def control_device(
    device_id: str,
    action: str,
    params: dict[str, Any] | None = None,
) -> dict:
    """Control a smart home device.

    Args:
        device_id: Device identifier, e.g. "light_living_01".
        action: One of: turn_on, turn_off, set, toggle.
        params: Action parameters (brightness, temperature, color, etc.).

    Returns:
        Updated device state.
    """
    result = await device_control(device_id, action, params or {})
    return result.model_dump(mode="json")


# ---------------------------------------------------------------------------
# Automation rules
# ---------------------------------------------------------------------------

@mcp.tool()
async def manage_automation(
    action: str,
    rule_id: str | None = None,
    name: str | None = None,
    trigger: dict[str, Any] | None = None,
    conditions: list[dict[str, Any]] | None = None,
    actions: list[dict[str, Any]] | None = None,
    enabled: bool = True,
) -> dict | list[dict]:
    """Create, read, update, or delete automation rules.

    Args:
        action: One of: create, get, list, update, delete.
        rule_id: Rule identifier (required for get/update/delete).
        name: Human-readable name (required for create).
        trigger: Trigger definition with type and config.
        conditions: List of conditions that must all be true.
        actions: List of device actions to execute.
        enabled: Whether the rule is active (default true).

    Returns:
        The affected rule or list of rules.
    """
    result = await automation_rules(
        action=action,
        rule_id=rule_id,
        name=name,
        trigger=trigger,
        conditions=conditions,
        actions=actions,
        enabled=enabled,
    )
    if isinstance(result, list):
        return [r.model_dump(mode="json") for r in result]
    return result.model_dump(mode="json")


# ---------------------------------------------------------------------------
# Energy monitoring
# ---------------------------------------------------------------------------

@mcp.tool()
async def get_energy_usage(
    period: str = "day",
    device_id: str | None = None,
) -> dict:
    """Retrieve energy consumption data.

    Args:
        period: Time window -- hour, day, week, month, or year.
        device_id: Optional device filter. Omit for aggregate data.

    Returns:
        Energy report with per-device breakdown and totals.
    """
    result = await energy_monitor(period, device_id)
    return result.model_dump(mode="json")


# ---------------------------------------------------------------------------
# Scene management
# ---------------------------------------------------------------------------

@mcp.tool()
async def manage_scene(
    action: str,
    name: str | None = None,
    scene_id: str | None = None,
    devices: list[dict[str, Any]] | None = None,
) -> dict | list[dict]:
    """Manage multi-device scenes.

    Args:
        action: One of: create, activate, get, list, update, delete.
        name: Scene name (required for create).
        scene_id: Scene identifier (required for get/update/delete/activate).
        devices: List of device configurations with device_id, action, and params.

    Returns:
        The affected scene or list of scenes.
    """
    result = await scene_manager(
        action=action,
        name=name,
        scene_id=scene_id,
        devices=devices,
    )
    if isinstance(result, list):
        return [s.model_dump(mode="json") for s in result]
    return result.model_dump(mode="json")


# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

@mcp.resource("smarthome://devices")
async def list_devices() -> str:
    """List all connected smart home devices."""
    from tools.smart_home import _get_hub

    hub = _get_hub()
    devices = await hub.list_devices()
    lines = []
    for d in devices:
        status = "online" if d.get("online") else "offline"
        lines.append(f"- {d.get('name', d.get('id', '?'))} [{d.get('category', '?')}] ({status})")
    return "\n".join(lines) if lines else "No devices found."


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run(
        transport="{{MCP_TRANSPORT}}",
        host="{{MCP_HOST}}",
        port={{MCP_PORT}},
    )
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project |
| `{{MCP_TRANSPORT}}` | MCP transport: `stdio` or `sse` |
| `{{MCP_HOST}}` | Server host, e.g. `0.0.0.0` |
| `{{MCP_PORT}}` | Server port, e.g. `8100` |

## Usage

```bash
# stdio transport (for Claude Desktop, etc.)
python mcp_servers/smart_home_server.py

# SSE transport
MCP_TRANSPORT=sse python mcp_servers/smart_home_server.py
```
