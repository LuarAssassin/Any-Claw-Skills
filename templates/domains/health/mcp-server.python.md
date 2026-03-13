# Health MCP Server - Python

> MCP server exposing health domain tools via the FastMCP Python SDK.
> Replace `{{PROJECT_NAME}}` and `{{PACKAGE_NAME}}` with your project values.

## Dependencies

```
mcp>=1.0.0
pydantic>=2.0
python-dateutil>=2.8
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `{{PACKAGE_NAME}}_HOST` | Server bind address | `127.0.0.1` |
| `{{PACKAGE_NAME}}_PORT` | Server port | `3100` |

## Code

```python
"""{{PROJECT_NAME}} - Health MCP Server.

Exposes food recognition, medication tracking, health reminders,
and symptom assessment as MCP tools, plus a health-data resource.
"""

from __future__ import annotations

import json
import os
from datetime import datetime

from mcp.server.fastmcp import FastMCP

# Import the health tools (from tools.python.md in the same package)
from {{PACKAGE_NAME}}.tools import (
    food_recognition,
    medication_tracker,
    health_reminder,
    symptom_assessment,
)

server = FastMCP("{{PROJECT_NAME}}")

# ---------------------------------------------------------------------------
# MCP Tools
# ---------------------------------------------------------------------------


@server.tool()
async def recognize_food(description: str) -> str:
    """Estimate nutritional content from a food description.

    Args:
        description: Free-text description of the food item or meal,
            e.g. "grilled chicken breast with rice".

    Returns:
        JSON string with nutritional breakdown including calories,
        protein, carbs, fat, and fiber.
    """
    result = await food_recognition(description)
    return result.model_dump_json(indent=2)


@server.tool()
async def manage_medication(
    action: str,
    medication: str,
    dosage: str = "",
    schedule: str = "",
) -> str:
    """Create, list, update, or remove medication schedule entries.

    Args:
        action: One of 'add', 'list', 'update', 'remove'.
        medication: Name of the medication (e.g. 'Lisinopril').
        dosage: Dosage amount and unit (e.g. '10mg'). Required for 'add'.
        schedule: When to take it (e.g. 'once daily at 08:00').
            Required for 'add'.

    Returns:
        JSON string with operation status and message.
    """
    result = await medication_tracker(action, medication, dosage, schedule)
    return result.model_dump_json(indent=2)


@server.tool()
async def set_health_reminder(
    reminder_type: str,
    time: str,
    message: str,
) -> str:
    """Set a health-related reminder.

    Args:
        reminder_type: Category such as 'medication', 'water',
            'exercise', or 'sleep'.
        time: When to trigger, in HH:MM format (e.g. '08:00').
        message: Reminder text shown to the user.

    Returns:
        JSON string with the created reminder ID and confirmation.
    """
    result = await health_reminder(reminder_type, time, message)
    return result.model_dump_json(indent=2)


@server.tool()
async def assess_symptoms(symptoms: list[str]) -> str:
    """Provide general information about reported symptoms.

    This does NOT diagnose any condition. The response always includes
    a disclaimer advising the user to consult a healthcare professional.

    Args:
        symptoms: List of symptom descriptions, e.g.
            ['headache', 'fatigue', 'dizziness'].

    Returns:
        JSON string with possible categories, severity hint,
        recommendation, and medical disclaimer.
    """
    result = await symptom_assessment(symptoms)
    return result.model_dump_json(indent=2)


# ---------------------------------------------------------------------------
# MCP Resources
# ---------------------------------------------------------------------------


@server.resource("health://data/summary")
async def health_data_summary() -> str:
    """Return a summary of all tracked health data.

    Provides an overview of active medications, pending reminders,
    and the timestamp of the last update.
    """
    from {{PACKAGE_NAME}}.tools import _medications, _reminders

    active_meds = [
        {"medication": e.medication, "dosage": e.dosage, "schedule": e.schedule}
        for e in _medications.values()
        if e.active
    ]
    active_reminders = [
        {"type": e.reminder_type, "time": e.time, "message": e.message}
        for e in _reminders.values()
        if e.active
    ]

    summary = {
        "medications": active_meds,
        "reminders": active_reminders,
        "generated_at": datetime.utcnow().isoformat() + "Z",
    }
    return json.dumps(summary, indent=2)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    """Run the MCP server."""
    host = os.environ.get("{{PACKAGE_NAME}}_HOST", "127.0.0.1")
    port = int(os.environ.get("{{PACKAGE_NAME}}_PORT", "3100"))
    server.run(transport="stdio")


if __name__ == "__main__":
    main()
```
