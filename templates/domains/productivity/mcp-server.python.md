# Productivity MCP Server - Python (FastMCP)

```python
"""
MCP server exposing productivity tools via the FastMCP framework.

Requirements:
    pip install fastmcp pydantic

Run:
    python mcp_server.py
    # or
    fastmcp run mcp_server.py
"""

from __future__ import annotations

from typing import Optional

from fastmcp import FastMCP

# Import the tools from the productivity module (see tools.python.md)
from productivity_tools import (
    Task,
    CalendarEvent,
    Digest,
    Result,
    Summary,
    calendar_sync,
    document_summarizer,
    email_digest,
    task_manager,
)

mcp = FastMCP(
    "{{SERVER_NAME}}",
    description="Productivity assistant providing task, calendar, email, and document tools.",
)


# ---------------------------------------------------------------------------
# Task Management
# ---------------------------------------------------------------------------

@mcp.tool()
async def manage_task(
    action: str,
    title: str = "",
    priority: str = "medium",
    due_date: str = "",
    project: str = "{{DEFAULT_PROJECT}}",
    tags: list[str] | None = None,
) -> dict:
    """Create, list, update, complete, or delete tasks.

    Args:
        action: One of 'create', 'list', 'update', 'complete', 'delete'.
        title: Task title (required for create/update/complete/delete).
        priority: One of 'critical', 'high', 'medium', 'low'.
        due_date: Due date in ISO-8601 format (e.g. '2025-12-31').
        project: Project name for grouping tasks.
        tags: Optional list of tags for categorization.
    """
    result = await task_manager(
        action=action,
        title=title,
        priority=priority,
        due_date=due_date,
        project=project,
        tags=tags,
    )
    return result.model_dump()


# ---------------------------------------------------------------------------
# Calendar
# ---------------------------------------------------------------------------

@mcp.tool()
async def manage_calendar(
    action: str,
    title: str = "",
    start: str = "",
    end: str = "",
    location: str = "",
    attendees: list[str] | None = None,
    event_id: str = "",
    date_range_start: str = "",
    date_range_end: str = "",
) -> dict:
    """List, create, update, or delete calendar events.

    Args:
        action: One of 'list', 'create', 'update', 'delete'.
        title: Event title (for create/update).
        start: Start time in ISO-8601 format.
        end: End time in ISO-8601 format.
        location: Event location.
        attendees: List of attendee email addresses.
        event_id: Event ID (for update/delete).
        date_range_start: Filter events starting from this date.
        date_range_end: Filter events ending before this date.
    """
    event_data = None
    if action in ("create", "update", "delete"):
        event_data = {}
        if event_id:
            event_data["id"] = event_id
        if title:
            event_data["title"] = title
        if start:
            event_data["start"] = start
        if end:
            event_data["end"] = end
        if location:
            event_data["location"] = location
        if attendees:
            event_data["attendees"] = attendees

    result = await calendar_sync(
        action=action,
        event=event_data,
        date_range_start=date_range_start,
        date_range_end=date_range_end,
    )
    return result.model_dump()


# ---------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------

@mcp.tool()
async def get_email_digest(
    count: int = 10,
    filter: str = "unread",
    mailbox: str = "{{DEFAULT_MAILBOX}}",
) -> dict:
    """Fetch and summarize recent emails.

    Args:
        count: Maximum number of emails to include (default 10).
        filter: One of 'unread', 'urgent', 'action_needed', 'all'.
        mailbox: Mailbox identifier to query.
    """
    digest = await email_digest(count=count, filter=filter, mailbox=mailbox)
    return digest.model_dump()


# ---------------------------------------------------------------------------
# Document Summarization
# ---------------------------------------------------------------------------

@mcp.tool()
async def summarize_document(
    text: str,
    max_length: int = 300,
    extract_actions: bool = True,
) -> dict:
    """Summarize a document and extract key points and action items.

    Args:
        text: The full text of the document to summarize.
        max_length: Target summary length in words (default 300).
        extract_actions: Whether to extract action items (default true).
    """
    summary = await document_summarizer(
        text=text,
        max_length=max_length,
        extract_actions=extract_actions,
    )
    return summary.model_dump()


# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

@mcp.resource("productivity://status")
async def get_status() -> str:
    """Return current productivity system status."""
    from productivity_tools import _tasks, _events

    return (
        f"Tasks: {len(_tasks)} total, "
        f"{sum(1 for t in _tasks.values() if t.status == 'done')} done\n"
        f"Events: {len(_events)} scheduled"
    )


# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run(transport="{{MCP_TRANSPORT}}")
```
