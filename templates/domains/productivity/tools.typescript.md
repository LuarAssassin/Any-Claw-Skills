# Productivity Tools - TypeScript Implementation

```typescript
/**
 * Productivity tools for task management, calendar, email, and document summarization.
 *
 * Requirements:
 *   npm install zod uuid
 */

import { z } from "zod";
import { randomUUID } from "crypto";

// ---------------------------------------------------------------------------
// Schemas & Types
// ---------------------------------------------------------------------------

const PrioritySchema = z.enum(["critical", "high", "medium", "low"]);
type Priority = z.infer<typeof PrioritySchema>;

const TaskStatusSchema = z.enum(["todo", "in_progress", "done", "archived"]);
type TaskStatus = z.infer<typeof TaskStatusSchema>;

interface Task {
  id: string;
  title: string;
  priority: Priority;
  status: TaskStatus;
  dueDate: string | null;
  project: string;
  createdAt: string;
  tags: string[];
}

interface CalendarEvent {
  id: string;
  title: string;
  start: string;
  end: string;
  location: string | null;
  attendees: string[];
  description: string | null;
}

interface EmailMessage {
  id: string;
  sender: string;
  subject: string;
  snippet: string;
  receivedAt: string;
  isUrgent: boolean;
  actionNeeded: boolean;
}

interface Digest {
  total: number;
  urgentCount: number;
  actionNeededCount: number;
  messages: EmailMessage[];
  generatedAt: string;
}

interface Summary {
  originalLength: number;
  summaryLength: number;
  text: string;
  keyPoints: string[];
  actionItems: string[];
}

interface Result {
  success: boolean;
  message: string;
  data?: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Storage (replace with your persistence layer)
// ---------------------------------------------------------------------------

const tasks = new Map<string, Task>();
const events = new Map<string, CalendarEvent>();

// ---------------------------------------------------------------------------
// Task Manager
// ---------------------------------------------------------------------------

export async function taskManager(
  action: string,
  title = "",
  priority: Priority = "medium",
  dueDate = "",
  project = "{{DEFAULT_PROJECT}}",
  tags: string[] = [],
): Promise<Result> {
  switch (action) {
    case "create": {
      const id = randomUUID().slice(0, 8);
      const task: Task = {
        id,
        title,
        priority,
        status: "todo",
        dueDate: dueDate || null,
        project,
        createdAt: new Date().toISOString(),
        tags,
      };
      tasks.set(id, task);
      return { success: true, message: `Task '${title}' created.`, data: task as unknown as Record<string, unknown> };
    }

    case "list": {
      let filtered = Array.from(tasks.values());
      if (priority) filtered = filtered.filter((t) => t.priority === priority);
      if (project) filtered = filtered.filter((t) => t.project === project);
      return { success: true, message: `Found ${filtered.length} task(s).`, data: { tasks: filtered } };
    }

    case "update": {
      const task = findTaskByTitle(title);
      if (!task) return { success: false, message: `Task '${title}' not found.` };
      if (priority) task.priority = priority;
      if (dueDate) task.dueDate = dueDate;
      if (tags.length > 0) task.tags = tags;
      return { success: true, message: `Task '${title}' updated.`, data: task as unknown as Record<string, unknown> };
    }

    case "complete": {
      const task = findTaskByTitle(title);
      if (!task) return { success: false, message: `Task '${title}' not found.` };
      task.status = "done";
      return { success: true, message: `Task '${title}' marked as done.` };
    }

    case "delete": {
      const task = findTaskByTitle(title);
      if (!task) return { success: false, message: `Task '${title}' not found.` };
      tasks.delete(task.id);
      return { success: true, message: `Task '${title}' deleted.` };
    }

    default:
      return { success: false, message: `Unknown action '${action}'.` };
  }
}

function findTaskByTitle(title: string): Task | undefined {
  for (const task of tasks.values()) {
    if (task.title.toLowerCase() === title.toLowerCase()) return task;
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// Calendar Sync
// ---------------------------------------------------------------------------

export async function calendarSync(
  action: string,
  event?: Partial<CalendarEvent>,
  dateRangeStart = "",
  dateRangeEnd = "",
): Promise<Result> {
  switch (action) {
    case "list": {
      let all = Array.from(events.values());
      if (dateRangeStart) all = all.filter((e) => e.start >= dateRangeStart);
      if (dateRangeEnd) all = all.filter((e) => e.end <= dateRangeEnd);
      all.sort((a, b) => a.start.localeCompare(b.start));
      return { success: true, message: `${all.length} event(s) found.`, data: { events: all } };
    }

    case "create": {
      if (!event?.title || !event?.start || !event?.end) {
        return { success: false, message: "Event must have title, start, and end." };
      }
      const calEvent: CalendarEvent = {
        id: randomUUID().slice(0, 8),
        title: event.title,
        start: event.start,
        end: event.end,
        location: event.location ?? null,
        attendees: event.attendees ?? [],
        description: event.description ?? null,
      };
      const conflict = detectConflict(calEvent);
      events.set(calEvent.id, calEvent);
      let msg = `Event '${calEvent.title}' created.`;
      if (conflict) msg += ` Warning: conflicts with '${conflict.title}'.`;
      return { success: true, message: msg, data: calEvent as unknown as Record<string, unknown> };
    }

    case "update": {
      if (!event?.id) return { success: false, message: "Event with 'id' is required." };
      const existing = events.get(event.id);
      if (!existing) return { success: false, message: "Event not found." };
      Object.assign(existing, event, { id: existing.id });
      return { success: true, message: "Event updated.", data: existing as unknown as Record<string, unknown> };
    }

    case "delete": {
      if (!event?.id) return { success: false, message: "Event with 'id' is required." };
      if (!events.delete(event.id)) return { success: false, message: "Event not found." };
      return { success: true, message: "Event deleted." };
    }

    default:
      return { success: false, message: `Unknown action '${action}'.` };
  }
}

function detectConflict(newEvent: CalendarEvent): CalendarEvent | undefined {
  for (const existing of events.values()) {
    if (existing.start < newEvent.end && existing.end > newEvent.start) return existing;
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// Email Digest
// ---------------------------------------------------------------------------

const URGENT_KEYWORDS = ["urgent", "asap", "immediately", "critical", "deadline"];
const ACTION_KEYWORDS = ["please", "action required", "review", "approve", "sign", "respond"];

export async function emailDigest(
  count = 10,
  filter: "unread" | "urgent" | "action_needed" | "all" = "unread",
  mailbox = "{{DEFAULT_MAILBOX}}",
): Promise<Digest> {
  const rawMessages = await fetchEmails(mailbox, count, filter);

  let messages: EmailMessage[] = rawMessages.map((raw) => ({
    id: raw.id,
    sender: raw.from,
    subject: raw.subject,
    snippet: raw.snippet.slice(0, 200),
    receivedAt: raw.date,
    isUrgent: classifyUrgency(raw),
    actionNeeded: detectActionNeeded(raw),
  }));

  if (filter === "urgent") messages = messages.filter((m) => m.isUrgent);
  if (filter === "action_needed") messages = messages.filter((m) => m.actionNeeded);

  return {
    total: messages.length,
    urgentCount: messages.filter((m) => m.isUrgent).length,
    actionNeededCount: messages.filter((m) => m.actionNeeded).length,
    messages: messages.slice(0, count),
    generatedAt: new Date().toISOString(),
  };
}

async function fetchEmails(
  _mailbox: string,
  _count: number,
  _filter: string,
): Promise<Array<Record<string, string>>> {
  // {{EMAIL_PROVIDER_INTEGRATION}}
  return [];
}

function classifyUrgency(raw: Record<string, string>): boolean {
  const text = `${raw.subject ?? ""} ${raw.snippet ?? ""}`.toLowerCase();
  return URGENT_KEYWORDS.some((kw) => text.includes(kw));
}

function detectActionNeeded(raw: Record<string, string>): boolean {
  const text = `${raw.subject ?? ""} ${raw.snippet ?? ""}`.toLowerCase();
  return ACTION_KEYWORDS.some((kw) => text.includes(kw));
}

// ---------------------------------------------------------------------------
// Document Summarizer
// ---------------------------------------------------------------------------

export async function documentSummarizer(
  text: string,
  maxLength = 300,
  extractActions = true,
  llmEndpoint = "{{LLM_ENDPOINT}}",
  llmApiKey = "{{LLM_API_KEY}}",
): Promise<Summary> {
  const prompt =
    `Summarize the following document in at most ${maxLength} words. ` +
    `Return JSON with keys: summary, key_points (list), action_items (list).\n\n${text}`;

  const resp = await fetch(llmEndpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${llmApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "{{LLM_MODEL}}",
      messages: [{ role: "user", content: prompt }],
      temperature: 0.2,
    }),
  });

  if (!resp.ok) throw new Error(`LLM request failed: ${resp.status}`);
  const data = await resp.json();

  const content = data.choices[0].message.content;
  const parsed = JSON.parse(content);

  return {
    originalLength: text.split(/\s+/).length,
    summaryLength: parsed.summary.split(/\s+/).length,
    text: parsed.summary,
    keyPoints: parsed.key_points ?? [],
    actionItems: extractActions ? (parsed.action_items ?? []) : [],
  };
}
```
