# Productivity Tools - Python Implementation

```python
"""
Productivity tools for task management, calendar, email, and document summarization.

Requirements:
    pip install pydantic aiohttp python-dateutil
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class Priority(str, Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class TaskStatus(str, Enum):
    TODO = "todo"
    IN_PROGRESS = "in_progress"
    DONE = "done"
    ARCHIVED = "archived"


class Task(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:8])
    title: str
    priority: Priority = Priority.MEDIUM
    status: TaskStatus = TaskStatus.TODO
    due_date: Optional[str] = None
    project: str = "{{DEFAULT_PROJECT}}"
    created_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    tags: list[str] = Field(default_factory=list)


class CalendarEvent(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:8])
    title: str
    start: str
    end: str
    location: Optional[str] = None
    attendees: list[str] = Field(default_factory=list)
    description: Optional[str] = None


class EmailMessage(BaseModel):
    id: str
    sender: str
    subject: str
    snippet: str
    received_at: str
    is_urgent: bool = False
    action_needed: bool = False


class Digest(BaseModel):
    total: int
    urgent_count: int
    action_needed_count: int
    messages: list[EmailMessage]
    generated_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())


class Summary(BaseModel):
    original_length: int
    summary_length: int
    text: str
    key_points: list[str]
    action_items: list[str]


class Result(BaseModel):
    success: bool
    message: str
    data: Optional[dict] = None


# ---------------------------------------------------------------------------
# Storage (replace with your persistence layer)
# ---------------------------------------------------------------------------

_tasks: dict[str, Task] = {}
_events: dict[str, CalendarEvent] = {}


# ---------------------------------------------------------------------------
# Task Manager
# ---------------------------------------------------------------------------

async def task_manager(
    action: str,
    title: str = "",
    priority: str = "medium",
    due_date: str = "",
    project: str = "{{DEFAULT_PROJECT}}",
    tags: list[str] | None = None,
) -> Result:
    """Create, read, update, or delete tasks with priorities and due dates.

    Args:
        action: One of 'create', 'list', 'update', 'complete', 'delete'.
        title: Task title (required for create/update).
        priority: One of 'critical', 'high', 'medium', 'low'.
        due_date: ISO-8601 date string (e.g. '2025-12-31').
        project: Project name for grouping.
        tags: Optional list of tags.
    """
    if action == "create":
        task = Task(
            title=title,
            priority=Priority(priority),
            due_date=due_date or None,
            project=project,
            tags=tags or [],
        )
        _tasks[task.id] = task
        return Result(success=True, message=f"Task '{title}' created.", data=task.model_dump())

    if action == "list":
        filtered = list(_tasks.values())
        if priority:
            filtered = [t for t in filtered if t.priority == Priority(priority)]
        if project:
            filtered = [t for t in filtered if t.project == project]
        return Result(
            success=True,
            message=f"Found {len(filtered)} task(s).",
            data={"tasks": [t.model_dump() for t in filtered]},
        )

    if action == "update":
        task = _find_task_by_title(title)
        if not task:
            return Result(success=False, message=f"Task '{title}' not found.")
        if priority:
            task.priority = Priority(priority)
        if due_date:
            task.due_date = due_date
        if tags is not None:
            task.tags = tags
        return Result(success=True, message=f"Task '{title}' updated.", data=task.model_dump())

    if action == "complete":
        task = _find_task_by_title(title)
        if not task:
            return Result(success=False, message=f"Task '{title}' not found.")
        task.status = TaskStatus.DONE
        return Result(success=True, message=f"Task '{title}' marked as done.")

    if action == "delete":
        task = _find_task_by_title(title)
        if not task:
            return Result(success=False, message=f"Task '{title}' not found.")
        del _tasks[task.id]
        return Result(success=True, message=f"Task '{title}' deleted.")

    return Result(success=False, message=f"Unknown action '{action}'.")


def _find_task_by_title(title: str) -> Task | None:
    for task in _tasks.values():
        if task.title.lower() == title.lower():
            return task
    return None


# ---------------------------------------------------------------------------
# Calendar Sync
# ---------------------------------------------------------------------------

async def calendar_sync(
    action: str,
    event: dict | None = None,
    date_range_start: str = "",
    date_range_end: str = "",
) -> Result:
    """Perform calendar operations: list, create, update, or delete events.

    Args:
        action: One of 'list', 'create', 'update', 'delete'.
        event: Dict with event fields (title, start, end, location, attendees).
        date_range_start: ISO date to filter events from.
        date_range_end: ISO date to filter events until.
    """
    if action == "list":
        events = list(_events.values())
        if date_range_start:
            events = [e for e in events if e.start >= date_range_start]
        if date_range_end:
            events = [e for e in events if e.end <= date_range_end]
        events.sort(key=lambda e: e.start)
        return Result(
            success=True,
            message=f"{len(events)} event(s) found.",
            data={"events": [e.model_dump() for e in events]},
        )

    if action == "create":
        if not event:
            return Result(success=False, message="Event data is required for 'create'.")
        cal_event = CalendarEvent(**event)
        conflict = _detect_conflict(cal_event)
        _events[cal_event.id] = cal_event
        msg = f"Event '{cal_event.title}' created."
        if conflict:
            msg += f" Warning: conflicts with '{conflict.title}'."
        return Result(success=True, message=msg, data=cal_event.model_dump())

    if action == "update":
        if not event or "id" not in event:
            return Result(success=False, message="Event with 'id' is required for 'update'.")
        existing = _events.get(event["id"])
        if not existing:
            return Result(success=False, message=f"Event '{event['id']}' not found.")
        for key, value in event.items():
            if key != "id" and hasattr(existing, key):
                setattr(existing, key, value)
        return Result(success=True, message="Event updated.", data=existing.model_dump())

    if action == "delete":
        if not event or "id" not in event:
            return Result(success=False, message="Event with 'id' is required for 'delete'.")
        if event["id"] not in _events:
            return Result(success=False, message="Event not found.")
        del _events[event["id"]]
        return Result(success=True, message="Event deleted.")

    return Result(success=False, message=f"Unknown action '{action}'.")


def _detect_conflict(new_event: CalendarEvent) -> CalendarEvent | None:
    for existing in _events.values():
        if existing.start < new_event.end and existing.end > new_event.start:
            return existing
    return None


# ---------------------------------------------------------------------------
# Email Digest
# ---------------------------------------------------------------------------

async def email_digest(
    count: int = 10,
    filter: str = "unread",
    mailbox: str = "{{DEFAULT_MAILBOX}}",
) -> Digest:
    """Fetch and summarize recent emails.

    Args:
        count: Maximum number of emails to include.
        filter: One of 'unread', 'urgent', 'action_needed', 'all'.
        mailbox: Mailbox identifier to query.

    Returns:
        Digest with email summaries and statistics.
    """
    # Replace this with your email API integration
    # Example: IMAP, Gmail API, Microsoft Graph, etc.
    raw_messages = await _fetch_emails(mailbox, count, filter)

    messages = []
    for raw in raw_messages:
        messages.append(EmailMessage(
            id=raw["id"],
            sender=raw["from"],
            subject=raw["subject"],
            snippet=raw["snippet"][:200],
            received_at=raw["date"],
            is_urgent=_classify_urgency(raw),
            action_needed=_detect_action_needed(raw),
        ))

    if filter == "urgent":
        messages = [m for m in messages if m.is_urgent]
    elif filter == "action_needed":
        messages = [m for m in messages if m.action_needed]

    return Digest(
        total=len(messages),
        urgent_count=sum(1 for m in messages if m.is_urgent),
        action_needed_count=sum(1 for m in messages if m.action_needed),
        messages=messages[:count],
    )


async def _fetch_emails(mailbox: str, count: int, filter: str) -> list[dict]:
    """Stub: replace with actual email provider integration."""
    # {{EMAIL_PROVIDER_INTEGRATION}}
    return []


def _classify_urgency(raw: dict) -> bool:
    urgent_keywords = ["urgent", "asap", "immediately", "critical", "deadline"]
    text = f"{raw.get('subject', '')} {raw.get('snippet', '')}".lower()
    return any(kw in text for kw in urgent_keywords)


def _detect_action_needed(raw: dict) -> bool:
    action_keywords = ["please", "action required", "review", "approve", "sign", "respond"]
    text = f"{raw.get('subject', '')} {raw.get('snippet', '')}".lower()
    return any(kw in text for kw in action_keywords)


# ---------------------------------------------------------------------------
# Document Summarizer
# ---------------------------------------------------------------------------

async def document_summarizer(
    text: str,
    max_length: int = 300,
    extract_actions: bool = True,
    llm_endpoint: str = "{{LLM_ENDPOINT}}",
    llm_api_key: str = "{{LLM_API_KEY}}",
) -> Summary:
    """Summarize a document, extracting key points and action items.

    Args:
        text: Full text of the document.
        max_length: Target summary length in words.
        extract_actions: Whether to extract action items.
        llm_endpoint: URL for the summarization LLM.
        llm_api_key: API key for the LLM service.

    Returns:
        Summary with condensed text, key points, and action items.
    """
    import aiohttp

    prompt = (
        f"Summarize the following document in at most {max_length} words. "
        "Return JSON with keys: summary, key_points (list), action_items (list).\n\n"
        f"{text}"
    )

    async with aiohttp.ClientSession() as session:
        async with session.post(
            llm_endpoint,
            headers={
                "Authorization": f"Bearer {llm_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": "{{LLM_MODEL}}",
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.2,
            },
        ) as resp:
            resp.raise_for_status()
            data = await resp.json()

    import json
    content = data["choices"][0]["message"]["content"]
    parsed = json.loads(content)

    return Summary(
        original_length=len(text.split()),
        summary_length=len(parsed["summary"].split()),
        text=parsed["summary"],
        key_points=parsed.get("key_points", []),
        action_items=parsed.get("action_items", []) if extract_actions else [],
    )
```
