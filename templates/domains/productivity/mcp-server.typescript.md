# Productivity MCP Server - TypeScript (MCP SDK)

```typescript
/**
 * MCP server exposing productivity tools via the official @modelcontextprotocol/sdk.
 *
 * Requirements:
 *   npm install @modelcontextprotocol/sdk zod uuid
 *
 * Run:
 *   npx ts-node mcp-server.ts
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

// Import the tools from the productivity module (see tools.typescript.md)
import {
  taskManager,
  calendarSync,
  emailDigest,
  documentSummarizer,
} from "./productivity-tools.js";

const server = new McpServer({
  name: "{{SERVER_NAME}}",
  version: "{{SERVER_VERSION}}",
});

// ---------------------------------------------------------------------------
// Task Management
// ---------------------------------------------------------------------------

server.tool(
  "manage_task",
  "Create, list, update, complete, or delete tasks with priorities and due dates.",
  {
    action: z.enum(["create", "list", "update", "complete", "delete"]).describe("Operation to perform"),
    title: z.string().optional().default("").describe("Task title"),
    priority: z.enum(["critical", "high", "medium", "low"]).optional().default("medium").describe("Task priority"),
    due_date: z.string().optional().default("").describe("Due date in ISO-8601 format"),
    project: z.string().optional().default("{{DEFAULT_PROJECT}}").describe("Project name"),
    tags: z.array(z.string()).optional().default([]).describe("Tags for categorization"),
  },
  async ({ action, title, priority, due_date, project, tags }) => {
    const result = await taskManager(action, title, priority, due_date, project, tags);
    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(result, null, 2),
        },
      ],
    };
  },
);

// ---------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------

server.tool(
  "manage_calendar",
  "List, create, update, or delete calendar events. Detects scheduling conflicts.",
  {
    action: z.enum(["list", "create", "update", "delete"]).describe("Operation to perform"),
    title: z.string().optional().default("").describe("Event title"),
    start: z.string().optional().default("").describe("Start time in ISO-8601"),
    end: z.string().optional().default("").describe("End time in ISO-8601"),
    location: z.string().optional().default("").describe("Event location"),
    attendees: z.array(z.string()).optional().default([]).describe("Attendee emails"),
    event_id: z.string().optional().default("").describe("Event ID for update/delete"),
    date_range_start: z.string().optional().default("").describe("Filter: events from"),
    date_range_end: z.string().optional().default("").describe("Filter: events until"),
  },
  async ({ action, title, start, end, location, attendees, event_id, date_range_start, date_range_end }) => {
    let event: Record<string, unknown> | undefined;
    if (["create", "update", "delete"].includes(action)) {
      event = {};
      if (event_id) event.id = event_id;
      if (title) event.title = title;
      if (start) event.start = start;
      if (end) event.end = end;
      if (location) event.location = location;
      if (attendees.length > 0) event.attendees = attendees;
    }

    const result = await calendarSync(action, event, date_range_start, date_range_end);
    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(result, null, 2),
        },
      ],
    };
  },
);

// ---------------------------------------------------------------------------
// Email
// ---------------------------------------------------------------------------

server.tool(
  "get_email_digest",
  "Fetch and summarize recent emails with urgency classification.",
  {
    count: z.number().optional().default(10).describe("Max number of emails"),
    filter: z.enum(["unread", "urgent", "action_needed", "all"]).optional().default("unread").describe("Email filter"),
    mailbox: z.string().optional().default("{{DEFAULT_MAILBOX}}").describe("Mailbox identifier"),
  },
  async ({ count, filter, mailbox }) => {
    const digest = await emailDigest(count, filter, mailbox);
    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(digest, null, 2),
        },
      ],
    };
  },
);

// ---------------------------------------------------------------------------
// Document Summarization
// ---------------------------------------------------------------------------

server.tool(
  "summarize_document",
  "Summarize a document, extracting key points and action items.",
  {
    text: z.string().describe("Full document text"),
    max_length: z.number().optional().default(300).describe("Target summary length in words"),
    extract_actions: z.boolean().optional().default(true).describe("Extract action items"),
  },
  async ({ text, max_length, extract_actions }) => {
    const summary = await documentSummarizer(text, max_length, extract_actions);
    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(summary, null, 2),
        },
      ],
    };
  },
);

// ---------------------------------------------------------------------------
// Entry Point
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("{{SERVER_NAME}} MCP server running on stdio");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
```
