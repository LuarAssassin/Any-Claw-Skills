# MCP Server: Finance (TypeScript)

Template for a Model Context Protocol server exposing finance tools via the MCP SDK.

## Generated File: `mcp-servers/financeServer.ts`

```typescript
/**
 * Finance MCP server for {{PROJECT_NAME}}.
 *
 * Run with:
 *   npx tsx mcp-servers/financeServer.ts
 */

import { McpServer, ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

import {
  ExpenseCategory,
  BudgetPeriod,
  expenseTracker,
  investmentMonitor,
  budgetAlert,
  receiptScanner,
} from "../tools/financeTools.js";

const server = new McpServer({
  name: "{{PROJECT_NAME}}-finance",
  version: "1.0.0",
});

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

server.resource(
  "categories",
  "finance://categories",
  async () => ({
    contents: [
      {
        uri: "finance://categories",
        mimeType: "application/json",
        text: JSON.stringify(ExpenseCategory.options),
      },
    ],
  }),
);

server.resource(
  "budget-periods",
  "finance://budget-periods",
  async () => ({
    contents: [
      {
        uri: "finance://budget-periods",
        mimeType: "application/json",
        text: JSON.stringify(BudgetPeriod.options),
      },
    ],
  }),
);

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

server.tool(
  "track_expense",
  "Create, read, update, delete, list, or summarize expenses.",
  {
    action: z.enum(["create", "read", "update", "delete", "list", "summary"]),
    amount: z.number().optional(),
    category: z.string().optional(),
    description: z.string().optional(),
    expenseId: z.string().optional(),
    merchant: z.string().optional(),
    tags: z.array(z.string()).optional(),
  },
  async (params) => {
    const result = await expenseTracker({
      action: params.action,
      amount: params.amount,
      category: params.category,
      description: params.description,
      expenseId: params.expenseId,
      merchant: params.merchant,
      tags: params.tags,
    });
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  },
);

server.tool(
  "check_portfolio",
  "Check investment portfolio status, allocation, and performance.",
  {
    portfolio: z.string(),
    action: z.enum(["status", "allocation", "performance"]).default("status"),
  },
  async (params) => {
    const result = await investmentMonitor({
      portfolio: params.portfolio,
      action: params.action,
    });
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  },
);

server.tool(
  "set_budget_alert",
  "Set a spending threshold alert for a category.",
  {
    category: z.string(),
    threshold: z.number().positive(),
    period: z.enum(["daily", "weekly", "monthly", "quarterly", "yearly"]).default("monthly"),
  },
  async (params) => {
    const result = await budgetAlert({
      category: params.category,
      threshold: params.threshold,
      period: params.period,
    });
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  },
);

server.tool(
  "scan_receipt",
  "Extract structured data from a receipt image description.",
  {
    imageDescription: z.string().describe("Receipt text or OCR output"),
  },
  async (params) => {
    const result = await receiptScanner({
      imageDescription: params.imageDescription,
    });
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  },
);

// ---------------------------------------------------------------------------
// Prompts
// ---------------------------------------------------------------------------

server.prompt(
  "monthly_summary",
  "Generate a monthly expense summary grouped by category.",
  {},
  async () => {
    const now = new Date();
    const month = now.toLocaleString("default", { month: "long", year: "numeric" });
    return {
      messages: [
        {
          role: "user",
          content: {
            type: "text",
            text: `Please generate a summary of my expenses for ${month}. Group by category, show totals, and flag any categories where spending exceeds my budget alerts.`,
          },
        },
      ],
    };
  },
);

server.prompt(
  "budget_check",
  "Check all active budget alerts and highlight those near threshold.",
  {},
  async () => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text: "Check all my active budget alerts. For each one, show the category, threshold, current spend, and remaining amount. Highlight any that are above 80% of the threshold.",
        },
      },
    ],
  }),
);

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Finance MCP server failed to start:", err);
  process.exit(1);
});
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the assistant project |
| `{{DEFAULT_CURRENCY}}` | Default currency code (e.g., USD, EUR) |

## Dependencies

```json
{
  "@modelcontextprotocol/sdk": "^1.0.0",
  "zod": "^3.22.0"
}
```

## MCP Client Configuration

```json
{
  "mcpServers": {
    "{{PROJECT_NAME}}-finance": {
      "command": "npx",
      "args": ["tsx", "mcp-servers/financeServer.ts"]
    }
  }
}
```
