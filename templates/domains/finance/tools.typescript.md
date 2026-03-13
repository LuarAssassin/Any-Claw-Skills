# Domain Tools: Finance (TypeScript)

Template for finance domain tool implementations using TypeScript with Zod validation.

## Generated File: `tools/financeTools.ts`

```typescript
/**
 * Finance domain tools for {{PROJECT_NAME}}.
 */

import { z } from "zod";
import { randomUUID } from "crypto";

// ---------------------------------------------------------------------------
// Schemas
// ---------------------------------------------------------------------------

export const ExpenseCategory = z.enum([
  "housing",
  "transportation",
  "food",
  "utilities",
  "healthcare",
  "insurance",
  "entertainment",
  "clothing",
  "education",
  "savings",
  "personal",
  "debt",
  "gifts",
  "other",
]);
export type ExpenseCategory = z.infer<typeof ExpenseCategory>;

export const BudgetPeriod = z.enum([
  "daily",
  "weekly",
  "monthly",
  "quarterly",
  "yearly",
]);
export type BudgetPeriod = z.infer<typeof BudgetPeriod>;

export const ExpenseSchema = z.object({
  id: z.string().default(() => randomUUID().slice(0, 12)),
  amount: z.number().positive(),
  category: ExpenseCategory,
  description: z.string().min(1).max(256),
  date: z.string().date().default(() => new Date().toISOString().slice(0, 10)),
  merchant: z.string().optional(),
  tags: z.array(z.string()).default([]),
  createdAt: z.string().datetime().default(() => new Date().toISOString()),
});
export type Expense = z.infer<typeof ExpenseSchema>;

export const PortfolioHoldingSchema = z.object({
  symbol: z.string(),
  name: z.string(),
  quantity: z.number(),
  costBasis: z.number(),
  currentPrice: z.number(),
  gainLoss: z.number().default(0),
  gainLossPct: z.number().default(0),
});
export type PortfolioHolding = z.infer<typeof PortfolioHoldingSchema>;

export const PortfolioStatusSchema = z.object({
  portfolio: z.string(),
  totalValue: z.number(),
  totalCost: z.number(),
  totalGainLoss: z.number(),
  totalGainLossPct: z.number(),
  holdings: z.array(PortfolioHoldingSchema),
  lastUpdated: z.string().datetime(),
  currency: z.string().default("{{DEFAULT_CURRENCY}}"),
});
export type PortfolioStatus = z.infer<typeof PortfolioStatusSchema>;

export const AlertConfigSchema = z.object({
  id: z.string().default(() => randomUUID().slice(0, 12)),
  category: ExpenseCategory,
  threshold: z.number().positive(),
  period: BudgetPeriod,
  currentSpend: z.number().default(0),
  remaining: z.number().default(0),
  isActive: z.boolean().default(true),
  createdAt: z.string().datetime().default(() => new Date().toISOString()),
});
export type AlertConfig = z.infer<typeof AlertConfigSchema>;

export const ReceiptLineItemSchema = z.object({
  description: z.string(),
  quantity: z.number().int().default(1),
  unitPrice: z.number(),
  total: z.number(),
});

export const ReceiptDataSchema = z.object({
  merchant: z.string(),
  date: z.string().date().optional(),
  subtotal: z.number().optional(),
  tax: z.number().optional(),
  total: z.number(),
  currency: z.string().default("{{DEFAULT_CURRENCY}}"),
  lineItems: z.array(ReceiptLineItemSchema).default([]),
  paymentMethod: z.string().optional(),
  confidence: z.number().min(0).max(1).default(0),
});
export type ReceiptData = z.infer<typeof ReceiptDataSchema>;

// ---------------------------------------------------------------------------
// Storage (swap for your DB in production)
// ---------------------------------------------------------------------------

const expenses = new Map<string, Expense>();
const alerts = new Map<string, AlertConfig>();
const portfolios = new Map<string, PortfolioHolding[]>();

// ---------------------------------------------------------------------------
// Tool implementations
// ---------------------------------------------------------------------------

export interface ExpenseResult {
  success: boolean;
  message: string;
  expense?: Expense;
  expenses?: Expense[];
  total?: number;
}

export async function expenseTracker(params: {
  action: "create" | "read" | "update" | "delete" | "list" | "summary";
  amount?: number;
  category?: string;
  description?: string;
  expenseId?: string;
  merchant?: string;
  tags?: string[];
}): Promise<ExpenseResult> {
  const { action, amount, category, description, expenseId, merchant, tags } =
    params;
  const cat = ExpenseCategory.parse(category ?? "other");

  if (action === "create") {
    const expense = ExpenseSchema.parse({
      amount,
      category: cat,
      description: description ?? "",
      merchant,
      tags: tags ?? [],
    });
    expenses.set(expense.id, expense);
    return { success: true, message: `Recorded ${amount?.toFixed(2)} expense`, expense };
  }

  if (action === "read") {
    if (!expenseId) return { success: false, message: "expenseId is required" };
    const exp = expenses.get(expenseId);
    if (!exp) return { success: false, message: `Expense ${expenseId} not found` };
    return { success: true, message: "Found", expense: exp };
  }

  if (action === "update") {
    if (!expenseId) return { success: false, message: "expenseId is required" };
    const existing = expenses.get(expenseId);
    if (!existing) return { success: false, message: `Expense ${expenseId} not found` };
    const updated: Expense = {
      ...existing,
      ...(amount !== undefined && { amount }),
      ...(category !== undefined && { category: cat }),
      ...(description !== undefined && { description }),
      ...(merchant !== undefined && { merchant }),
      ...(tags !== undefined && { tags }),
    };
    expenses.set(expenseId, updated);
    return { success: true, message: "Updated", expense: updated };
  }

  if (action === "delete") {
    if (!expenseId) return { success: false, message: "expenseId is required" };
    const deleted = expenses.delete(expenseId);
    return { success: deleted, message: deleted ? "Deleted" : `Not found` };
  }

  if (action === "list") {
    let results = Array.from(expenses.values());
    if (category && category !== "other") {
      results = results.filter((e) => e.category === cat);
    }
    results.sort((a, b) => b.date.localeCompare(a.date));
    const total = results.reduce((sum, e) => sum + e.amount, 0);
    return { success: true, message: `Found ${results.length} expenses`, expenses: results, total };
  }

  if (action === "summary") {
    const all = Array.from(expenses.values());
    const byCat: Record<string, number> = {};
    for (const e of all) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    const total = Object.values(byCat).reduce((s, v) => s + v, 0);
    const lines = Object.entries(byCat)
      .sort()
      .map(([k, v]) => `  ${k}: ${v.toFixed(2)}`);
    return { success: true, message: `Total: ${total.toFixed(2)}\n${lines.join("\n")}`, expenses: all, total };
  }

  return { success: false, message: `Unknown action: ${action}` };
}

export async function investmentMonitor(params: {
  portfolio: string;
  action?: "status" | "allocation" | "performance";
}): Promise<PortfolioStatus> {
  const holdings = portfolios.get(params.portfolio) ?? [];

  for (const h of holdings) {
    h.gainLoss = (h.currentPrice - h.costBasis) * h.quantity;
    h.gainLossPct = h.costBasis ? ((h.currentPrice / h.costBasis) - 1) * 100 : 0;
  }

  const totalValue = holdings.reduce((s, h) => s + h.currentPrice * h.quantity, 0);
  const totalCost = holdings.reduce((s, h) => s + h.costBasis * h.quantity, 0);
  const totalGL = totalValue - totalCost;
  const totalGLPct = totalCost ? ((totalValue / totalCost) - 1) * 100 : 0;

  return {
    portfolio: params.portfolio,
    totalValue: Math.round(totalValue * 100) / 100,
    totalCost: Math.round(totalCost * 100) / 100,
    totalGainLoss: Math.round(totalGL * 100) / 100,
    totalGainLossPct: Math.round(totalGLPct * 100) / 100,
    holdings,
    lastUpdated: new Date().toISOString(),
    currency: "{{DEFAULT_CURRENCY}}",
  };
}

export async function budgetAlert(params: {
  category: string;
  threshold: number;
  period?: string;
}): Promise<AlertConfig> {
  const cat = ExpenseCategory.parse(params.category.toLowerCase());
  const period = BudgetPeriod.parse(params.period?.toLowerCase() ?? "monthly");

  const allExpenses = Array.from(expenses.values()).filter(
    (e) => e.category === cat,
  );
  const currentSpend = allExpenses.reduce((s, e) => s + e.amount, 0);

  const alert = AlertConfigSchema.parse({
    category: cat,
    threshold: params.threshold,
    period,
    currentSpend: Math.round(currentSpend * 100) / 100,
    remaining: Math.round(Math.max(params.threshold - currentSpend, 0) * 100) / 100,
  });

  alerts.set(alert.id, alert);
  return alert;
}

export async function receiptScanner(params: {
  imageDescription: string;
}): Promise<ReceiptData> {
  const lines = params.imageDescription.trim().split("\n");
  const merchant = lines[0]?.trim() ?? "Unknown";

  const lineItems: z.infer<typeof ReceiptLineItemSchema>[] = [];
  let total = 0;
  let tax = 0;
  let receiptDate: string | undefined;

  for (const line of lines.slice(1)) {
    const lower = line.toLowerCase().trim();
    if (lower.startsWith("date:")) {
      receiptDate = lower.replace("date:", "").trim();
    } else if (lower.startsWith("tax:")) {
      tax = parseFloat(lower.replace("tax:", "").replace("$", "").trim()) || 0;
    } else if (lower.startsWith("total:")) {
      total = parseFloat(lower.replace("total:", "").replace("$", "").trim()) || 0;
    } else if (line.includes("$")) {
      const parts = line.split("$");
      if (parts.length === 2) {
        const price = parseFloat(parts[1].trim());
        if (!isNaN(price)) {
          lineItems.push({
            description: parts[0].trim(),
            quantity: 1,
            unitPrice: price,
            total: price,
          });
        }
      }
    }
  }

  if (total === 0 && lineItems.length > 0) {
    total = lineItems.reduce((s, i) => s + i.total, 0) + tax;
  }

  const subtotal = tax ? total - tax : undefined;

  return {
    merchant,
    date: receiptDate,
    subtotal: subtotal !== undefined ? Math.round(subtotal * 100) / 100 : undefined,
    tax: tax || undefined,
    total: Math.round(total * 100) / 100,
    currency: "{{DEFAULT_CURRENCY}}",
    lineItems,
    confidence: 0.7,
  };
}

// ---------------------------------------------------------------------------
// Tool registry for agent integration
// ---------------------------------------------------------------------------

export const FINANCE_TOOLS = [
  {
    name: "expense_tracker",
    description: "Create, read, update, delete, list, or summarize expense records.",
    parameters: ExpenseSchema.omit({ id: true, createdAt: true }).extend({
      action: z.enum(["create", "read", "update", "delete", "list", "summary"]),
      expenseId: z.string().optional(),
    }),
    handler: expenseTracker,
  },
  {
    name: "investment_monitor",
    description: "Check portfolio status, allocation, and performance.",
    parameters: z.object({
      portfolio: z.string(),
      action: z.enum(["status", "allocation", "performance"]).default("status"),
    }),
    handler: investmentMonitor,
  },
  {
    name: "budget_alert",
    description: "Set a budget threshold alert for a spending category.",
    parameters: z.object({
      category: ExpenseCategory,
      threshold: z.number().positive(),
      period: BudgetPeriod.default("monthly"),
    }),
    handler: budgetAlert,
  },
  {
    name: "receipt_scanner",
    description: "Extract structured data from a receipt description.",
    parameters: z.object({
      imageDescription: z.string().describe("Receipt text or OCR output"),
    }),
    handler: receiptScanner,
  },
] as const;
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the assistant project |
| `{{DEFAULT_CURRENCY}}` | Default currency code (e.g., USD, EUR) |

## Dependencies

```json
{
  "zod": "^3.22.0"
}
```
