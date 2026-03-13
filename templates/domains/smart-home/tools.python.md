# Smart Home Tools (Python)

Python tool implementations for smart home device control, automation, energy monitoring, and scene management.

## Dependencies

```
pydantic>=2.0
aiohttp>=3.9
```

## Generated File: `tools/smart_home.py`

```python
"""Smart home domain tools for {{PROJECT_NAME}}."""

import asyncio
from datetime import datetime, timedelta
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class DeviceCategory(str, Enum):
    LIGHT = "light"
    SWITCH = "switch"
    THERMOSTAT = "thermostat"
    LOCK = "lock"
    SENSOR = "sensor"
    CAMERA = "camera"
    BLINDS = "blinds"
    SPEAKER = "speaker"
    APPLIANCE = "appliance"


class DeviceState(BaseModel):
    device_id: str
    name: str
    category: DeviceCategory
    online: bool
    state: dict[str, Any] = Field(default_factory=dict)
    last_updated: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        json_schema_extra = {
            "example": {
                "device_id": "light_living_01",
                "name": "Living Room Ceiling",
                "category": "light",
                "online": True,
                "state": {"on": True, "brightness": 80, "color_temp": 3500},
                "last_updated": "2026-03-13T10:30:00Z",
            }
        }


class TriggerType(str, Enum):
    TIME = "time"
    DEVICE_STATE = "device_state"
    SUNRISE = "sunrise"
    SUNSET = "sunset"
    GEOFENCE = "geofence"
    WEBHOOK = "webhook"


class Trigger(BaseModel):
    type: TriggerType
    config: dict[str, Any] = Field(default_factory=dict)


class Condition(BaseModel):
    device_id: str | None = None
    attribute: str
    operator: str  # eq, ne, gt, lt, gte, lte
    value: Any


class AutomationAction(BaseModel):
    device_id: str
    action: str
    params: dict[str, Any] = Field(default_factory=dict)


class Rule(BaseModel):
    rule_id: str
    name: str
    enabled: bool = True
    trigger: Trigger
    conditions: list[Condition] = Field(default_factory=list)
    actions: list[AutomationAction] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    last_triggered: datetime | None = None


class EnergyEntry(BaseModel):
    device_id: str | None = None
    device_name: str | None = None
    period: str
    kwh: float
    cost: float
    avg_watts: float


class EnergyReport(BaseModel):
    period: str
    start: datetime
    end: datetime
    entries: list[EnergyEntry] = Field(default_factory=list)
    total_kwh: float = 0.0
    total_cost: float = 0.0


class Scene(BaseModel):
    scene_id: str
    name: str
    devices: list[dict[str, Any]] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# Hub client stub
# ---------------------------------------------------------------------------

class SmartHomeHub:
    """Client for the smart home hub ({{HUB_PLATFORM}})."""

    def __init__(self, base_url: str, token: str):
        self.base_url = base_url.rstrip("/")
        self.token = token

    async def _request(self, method: str, path: str, body: dict | None = None) -> dict:
        import aiohttp

        url = f"{self.base_url}{path}"
        headers = {"Authorization": f"Bearer {self.token}"}
        async with aiohttp.ClientSession() as session:
            async with session.request(method, url, json=body, headers=headers) as resp:
                resp.raise_for_status()
                return await resp.json()

    async def get_device(self, device_id: str) -> dict:
        return await self._request("GET", f"/devices/{device_id}")

    async def set_device(self, device_id: str, action: str, params: dict) -> dict:
        return await self._request("POST", f"/devices/{device_id}/{action}", params)

    async def list_devices(self) -> list[dict]:
        data = await self._request("GET", "/devices")
        return data.get("devices", [])

    async def get_energy(self, period: str, device_id: str | None) -> dict:
        path = "/energy"
        qs = f"?period={period}"
        if device_id:
            qs += f"&device_id={device_id}"
        return await self._request("GET", f"{path}{qs}")


# ---------------------------------------------------------------------------
# Tool functions
# ---------------------------------------------------------------------------

_hub: SmartHomeHub | None = None


def _get_hub() -> SmartHomeHub:
    global _hub
    if _hub is None:
        _hub = SmartHomeHub(
            base_url="{{HUB_URL}}",
            token="{{HUB_TOKEN}}",
        )
    return _hub


async def device_control(
    device_id: str,
    action: str,
    params: dict[str, Any] | None = None,
) -> DeviceState:
    """Control a smart home device.

    Args:
        device_id: Unique identifier of the device (e.g. ``light_living_01``).
        action: Action to perform: ``turn_on``, ``turn_off``, ``set``, ``toggle``.
        params: Action-specific parameters (brightness, temperature, color, etc.).

    Returns:
        Updated device state after the action is applied.
    """
    hub = _get_hub()
    params = params or {}

    SECURITY_DEVICES = {"lock", "alarm", "garage_door"}
    device_data = await hub.get_device(device_id)
    category = device_data.get("category", "")

    if category in SECURITY_DEVICES and action in ("unlock", "open", "disarm"):
        # Security actions are logged and require confirmation upstream
        pass

    result = await hub.set_device(device_id, action, params)

    return DeviceState(
        device_id=device_id,
        name=result.get("name", device_id),
        category=result.get("category", "switch"),
        online=result.get("online", True),
        state=result.get("state", {}),
        last_updated=datetime.utcnow(),
    )


async def automation_rules(
    action: str,
    rule_id: str | None = None,
    name: str | None = None,
    trigger: dict[str, Any] | None = None,
    conditions: list[dict[str, Any]] | None = None,
    actions: list[dict[str, Any]] | None = None,
    enabled: bool = True,
) -> Rule | list[Rule]:
    """Create, read, update, or delete automation rules.

    Args:
        action: CRUD operation -- ``create``, ``get``, ``list``, ``update``, ``delete``.
        rule_id: Rule identifier (required for get/update/delete).
        name: Human-readable rule name (required for create).
        trigger: Trigger definition (type + config).
        conditions: Optional list of conditions that must all be true.
        actions: List of device actions to execute when the rule fires.
        enabled: Whether the rule is active.

    Returns:
        The affected Rule, or a list of Rules for ``list``.
    """
    hub = _get_hub()

    if action == "create":
        if not name or not trigger or not actions:
            raise ValueError("create requires name, trigger, and actions")
        parsed_trigger = Trigger(**trigger)
        parsed_conditions = [Condition(**c) for c in (conditions or [])]
        parsed_actions = [AutomationAction(**a) for a in actions]
        body = {
            "name": name,
            "enabled": enabled,
            "trigger": parsed_trigger.model_dump(),
            "conditions": [c.model_dump() for c in parsed_conditions],
            "actions": [a.model_dump() for a in parsed_actions],
        }
        result = await hub._request("POST", "/automations", body)
        return Rule(**result)

    if action == "get":
        if not rule_id:
            raise ValueError("get requires rule_id")
        result = await hub._request("GET", f"/automations/{rule_id}")
        return Rule(**result)

    if action == "list":
        result = await hub._request("GET", "/automations")
        return [Rule(**r) for r in result.get("rules", [])]

    if action == "update":
        if not rule_id:
            raise ValueError("update requires rule_id")
        body: dict[str, Any] = {}
        if name is not None:
            body["name"] = name
        if trigger is not None:
            body["trigger"] = Trigger(**trigger).model_dump()
        if conditions is not None:
            body["conditions"] = [Condition(**c).model_dump() for c in conditions]
        if actions is not None:
            body["actions"] = [AutomationAction(**a).model_dump() for a in actions]
        body["enabled"] = enabled
        result = await hub._request("PATCH", f"/automations/{rule_id}", body)
        return Rule(**result)

    if action == "delete":
        if not rule_id:
            raise ValueError("delete requires rule_id")
        await hub._request("DELETE", f"/automations/{rule_id}")
        return Rule(rule_id=rule_id, name="(deleted)")

    raise ValueError(f"Unknown action: {action}")


async def energy_monitor(
    period: str = "day",
    device_id: str | None = None,
) -> EnergyReport:
    """Retrieve energy consumption data.

    Args:
        period: Time window -- ``hour``, ``day``, ``week``, ``month``, ``year``.
        device_id: Optional device to filter by. ``None`` returns aggregate data.

    Returns:
        EnergyReport with per-device breakdown and totals.
    """
    hub = _get_hub()
    data = await hub.get_energy(period, device_id)

    entries = []
    total_kwh = 0.0
    rate = {{ENERGY_RATE_FLOAT}}  # dollars per kWh

    for item in data.get("entries", []):
        kwh = item.get("kwh", 0.0)
        total_kwh += kwh
        entries.append(
            EnergyEntry(
                device_id=item.get("device_id"),
                device_name=item.get("device_name"),
                period=period,
                kwh=round(kwh, 3),
                cost=round(kwh * rate, 2),
                avg_watts=round(item.get("avg_watts", 0.0), 1),
            )
        )

    period_hours = {"hour": 1, "day": 24, "week": 168, "month": 720, "year": 8760}
    now = datetime.utcnow()
    hours = period_hours.get(period, 24)

    return EnergyReport(
        period=period,
        start=now - timedelta(hours=hours),
        end=now,
        entries=entries,
        total_kwh=round(total_kwh, 3),
        total_cost=round(total_kwh * rate, 2),
    )


async def scene_manager(
    action: str,
    name: str | None = None,
    scene_id: str | None = None,
    devices: list[dict[str, Any]] | None = None,
) -> Scene | list[Scene]:
    """Manage multi-device scenes.

    Args:
        action: ``create``, ``activate``, ``get``, ``list``, ``update``, ``delete``.
        name: Scene name (required for create).
        scene_id: Scene identifier (required for get/update/delete/activate).
        devices: List of dicts with ``device_id``, ``action``, and ``params`` keys.

    Returns:
        The affected Scene, or a list of Scenes for ``list``.
    """
    hub = _get_hub()

    if action == "create":
        if not name or not devices:
            raise ValueError("create requires name and devices")
        body = {"name": name, "devices": devices}
        result = await hub._request("POST", "/scenes", body)
        return Scene(**result)

    if action == "activate":
        if not scene_id:
            raise ValueError("activate requires scene_id")
        result = await hub._request("POST", f"/scenes/{scene_id}/activate")
        return Scene(**result)

    if action == "get":
        if not scene_id:
            raise ValueError("get requires scene_id")
        result = await hub._request("GET", f"/scenes/{scene_id}")
        return Scene(**result)

    if action == "list":
        result = await hub._request("GET", "/scenes")
        return [Scene(**s) for s in result.get("scenes", [])]

    if action == "update":
        if not scene_id:
            raise ValueError("update requires scene_id")
        body: dict[str, Any] = {}
        if name is not None:
            body["name"] = name
        if devices is not None:
            body["devices"] = devices
        result = await hub._request("PATCH", f"/scenes/{scene_id}", body)
        return Scene(**result)

    if action == "delete":
        if not scene_id:
            raise ValueError("delete requires scene_id")
        await hub._request("DELETE", f"/scenes/{scene_id}")
        return Scene(scene_id=scene_id, name="(deleted)")

    raise ValueError(f"Unknown action: {action}")
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project |
| `{{HUB_PLATFORM}}` | Smart home hub platform (e.g. Home Assistant, SmartThings) |
| `{{HUB_URL}}` | Hub API base URL |
| `{{HUB_TOKEN}}` | Hub API authentication token |
| `{{ENERGY_RATE_FLOAT}}` | Energy rate as a float, e.g. `0.12` |
