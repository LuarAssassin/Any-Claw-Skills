# Health MCP Server - TypeScript

> MCP server exposing health domain tools via the `@modelcontextprotocol/sdk`.
> Replace `{{PROJECT_NAME}}` and `{{PACKAGE_NAME}}` with your project values.

## Dependencies

```json
{
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "zod": "^3.22.0",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "@types/uuid": "^9.0.0",
    "typescript": "^5.3.0"
  }
}
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `{{PACKAGE_NAME}}_HOST` | Server bind address | `127.0.0.1` |
| `{{PACKAGE_NAME}}_PORT` | Server port | `3100` |

## Code

```typescript
/**
 * {{PROJECT_NAME}} - Health MCP Server.
 *
 * Exposes food recognition, medication tracking, health reminders,
 * and symptom assessment as MCP tools, plus a health-data resource.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

// Import the health tools (from tools.typescript.md in the same package)
import {
  foodRecognition,
  medicationTracker,
  healthReminder,
  symptomAssessment,
} from "./tools.js";

const server = new McpServer({
  name: "{{PROJECT_NAME}}",
  version: "1.0.0",
});

// ---------------------------------------------------------------------------
// MCP Tools
// ---------------------------------------------------------------------------

server.tool(
  "recognize_food",
  "Estimate nutritional content from a food description. Returns calories, protein, carbs, fat, and fiber.",
  {
    description: z.string().describe(
      "Free-text description of the food item or meal, e.g. 'grilled chicken breast with rice'"
    ),
  },
  async ({ description }) => {
    const result = await foodRecognition(description);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  }
);

server.tool(
  "manage_medication",
  "Create, list, update, or remove medication schedule entries.",
  {
    action: z.enum(["add", "list", "update", "remove"]).describe("Operation to perform"),
    medication: z.string().describe("Name of the medication"),
    dosage: z.string().default("").describe("Dosage amount and unit, e.g. '10mg'"),
    schedule: z.string().default("").describe("When to take it, e.g. 'once daily at 08:00'"),
  },
  async ({ action, medication, dosage, schedule }) => {
    const result = await medicationTracker(action, medication, dosage, schedule);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  }
);

server.tool(
  "set_health_reminder",
  "Set a health-related reminder for medication, water intake, exercise, or sleep.",
  {
    reminder_type: z.enum(["medication", "water", "exercise", "sleep"]).describe("Reminder category"),
    time: z.string().describe("When to trigger, in HH:MM format"),
    message: z.string().describe("Reminder text shown to the user"),
  },
  async ({ reminder_type, time, message }) => {
    const result = await healthReminder(reminder_type, time, message);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  }
);

server.tool(
  "assess_symptoms",
  "Provide general information about reported symptoms. NOT a medical diagnosis. Always includes a disclaimer.",
  {
    symptoms: z.array(z.string()).describe("List of symptom descriptions, e.g. ['headache', 'fatigue']"),
  },
  async ({ symptoms }) => {
    const result = await symptomAssessment(symptoms);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  }
);

// ---------------------------------------------------------------------------
// MCP Resources
// ---------------------------------------------------------------------------

server.resource(
  "health_data_summary",
  "health://data/summary",
  async (uri) => {
    // In a real implementation, this would read from the persistent stores
    // used by the tool functions. This example returns a placeholder.
    const summary = {
      medications: [],
      reminders: [],
      generated_at: new Date().toISOString(),
    };
    return {
      contents: [
        {
          uri: uri.href,
          mimeType: "application/json",
          text: JSON.stringify(summary, null, 2),
        },
      ],
    };
  }
);

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
```
