# Domain Tools: Finance (Python)

Template for finance domain tool implementations using Pydantic models and async patterns.

## Generated File: `tools/finance_tools.py`

```python
"""Finance domain tools for {{PROJECT_NAME}}."""

import uuid
from datetime import datetime, date
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class ExpenseCategory(str, Enum):
    HOUSING = "housing"
    TRANSPORTATION = "transportation"
    FOOD = "food"
    UTILITIES = "utilities"
    HEALTHCARE = "healthcare"
    INSURANCE = "insurance"
    ENTERTAINMENT = "entertainment"
    CLOTHING = "clothing"
    EDUCATION = "education"
    SAVINGS = "savings"
    PERSONAL = "personal"
    DEBT = "debt"
    GIFTS = "gifts"
    OTHER = "other"


class BudgetPeriod(str, Enum):
    DAILY = "daily"
    WEEKLY = "weekly"
    MONTHLY = "monthly"
    QUARTERLY = "quarterly"
    YEARLY = "yearly"


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class Expense(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    amount: float = Field(..., gt=0, description="Amount in {{DEFAULT_CURRENCY}}")
    category: ExpenseCategory
    description: str = Field(..., min_length=1, max_length=256)
    date: date = Field(default_factory=date.today)
    merchant: str | None = None
    tags: list[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class ExpenseResult(BaseModel):
    success: bool
    message: str
    expense: Expense | None = None
    expenses: list[Expense] = Field(default_factory=list)
    total: float | None = None


class PortfolioHolding(BaseModel):
    symbol: str
    name: str
    quantity: float
    cost_basis: float
    current_price: float
    gain_loss: float = 0.0
    gain_loss_pct: float = 0.0


class PortfolioStatus(BaseModel):
    portfolio: str
    total_value: float
    total_cost: float
    total_gain_loss: float
    total_gain_loss_pct: float
    holdings: list[PortfolioHolding]
    last_updated: datetime = Field(default_factory=datetime.utcnow)
    currency: str = "{{DEFAULT_CURRENCY}}"


class AlertConfig(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    category: ExpenseCategory
    threshold: float = Field(..., gt=0)
    period: BudgetPeriod
    current_spend: float = 0.0
    remaining: float = 0.0
    is_active: bool = True
    created_at: datetime = Field(default_factory=datetime.utcnow)


class ReceiptLineItem(BaseModel):
    description: str
    quantity: int = 1
    unit_price: float
    total: float


class ReceiptData(BaseModel):
    merchant: str
    date: date | None = None
    subtotal: float | None = None
    tax: float | None = None
    total: float
    currency: str = "{{DEFAULT_CURRENCY}}"
    line_items: list[ReceiptLineItem] = Field(default_factory=list)
    payment_method: str | None = None
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)


# ---------------------------------------------------------------------------
# Storage interface (swap for your DB implementation)
# ---------------------------------------------------------------------------

class FinanceStore:
    """In-memory store. Replace with {{STORAGE_BACKEND}} in production."""

    def __init__(self) -> None:
        self._expenses: dict[str, Expense] = {}
        self._alerts: dict[str, AlertConfig] = {}
        self._portfolios: dict[str, list[PortfolioHolding]] = {}

    async def save_expense(self, expense: Expense) -> None:
        self._expenses[expense.id] = expense

    async def get_expense(self, expense_id: str) -> Expense | None:
        return self._expenses.get(expense_id)

    async def delete_expense(self, expense_id: str) -> bool:
        return self._expenses.pop(expense_id, None) is not None

    async def list_expenses(
        self,
        category: ExpenseCategory | None = None,
        start_date: date | None = None,
        end_date: date | None = None,
    ) -> list[Expense]:
        results = list(self._expenses.values())
        if category:
            results = [e for e in results if e.category == category]
        if start_date:
            results = [e for e in results if e.date >= start_date]
        if end_date:
            results = [e for e in results if e.date <= end_date]
        return sorted(results, key=lambda e: e.date, reverse=True)

    async def save_alert(self, alert: AlertConfig) -> None:
        self._alerts[alert.id] = alert

    async def get_alerts(self, category: ExpenseCategory | None = None) -> list[AlertConfig]:
        alerts = list(self._alerts.values())
        if category:
            alerts = [a for a in alerts if a.category == category]
        return alerts

    async def save_portfolio(self, name: str, holdings: list[PortfolioHolding]) -> None:
        self._portfolios[name] = holdings

    async def get_portfolio(self, name: str) -> list[PortfolioHolding] | None:
        return self._portfolios.get(name)


_store = FinanceStore()


# ---------------------------------------------------------------------------
# Tool implementations
# ---------------------------------------------------------------------------

async def expense_tracker(
    action: str,
    amount: float = 0.0,
    category: str = "other",
    description: str = "",
    expense_id: str | None = None,
    merchant: str | None = None,
    tags: list[str] | None = None,
) -> ExpenseResult:
    """Create, read, update, or delete expense records.

    Args:
        action: One of "create", "read", "update", "delete", "list", "summary".
        amount: Transaction amount in {{DEFAULT_CURRENCY}} (required for create/update).
        category: Expense category (see ExpenseCategory enum).
        description: Short description of the expense.
        expense_id: Required for read, update, delete operations.
        merchant: Optional merchant name.
        tags: Optional list of tags for filtering.
    """
    cat = ExpenseCategory(category.lower())

    if action == "create":
        expense = Expense(
            amount=amount,
            category=cat,
            description=description,
            merchant=merchant,
            tags=tags or [],
        )
        await _store.save_expense(expense)
        return ExpenseResult(success=True, message=f"Recorded {amount:.2f} expense", expense=expense)

    if action == "read":
        if not expense_id:
            return ExpenseResult(success=False, message="expense_id is required for read")
        expense = await _store.get_expense(expense_id)
        if not expense:
            return ExpenseResult(success=False, message=f"Expense {expense_id} not found")
        return ExpenseResult(success=True, message="Found", expense=expense)

    if action == "update":
        if not expense_id:
            return ExpenseResult(success=False, message="expense_id is required for update")
        existing = await _store.get_expense(expense_id)
        if not existing:
            return ExpenseResult(success=False, message=f"Expense {expense_id} not found")
        updated = existing.model_copy(update={
            k: v for k, v in {
                "amount": amount or None,
                "category": cat,
                "description": description or None,
                "merchant": merchant,
                "tags": tags,
            }.items() if v is not None
        })
        await _store.save_expense(updated)
        return ExpenseResult(success=True, message="Updated", expense=updated)

    if action == "delete":
        if not expense_id:
            return ExpenseResult(success=False, message="expense_id is required for delete")
        deleted = await _store.delete_expense(expense_id)
        msg = "Deleted" if deleted else f"Expense {expense_id} not found"
        return ExpenseResult(success=deleted, message=msg)

    if action == "list":
        expenses = await _store.list_expenses(category=cat if category != "other" else None)
        total = sum(e.amount for e in expenses)
        return ExpenseResult(
            success=True,
            message=f"Found {len(expenses)} expenses",
            expenses=expenses,
            total=total,
        )

    if action == "summary":
        all_expenses = await _store.list_expenses()
        by_cat: dict[str, float] = {}
        for e in all_expenses:
            by_cat[e.category.value] = by_cat.get(e.category.value, 0.0) + e.amount
        total = sum(by_cat.values())
        summary_lines = [f"  {k}: {v:.2f}" for k, v in sorted(by_cat.items())]
        msg = f"Total: {total:.2f}\n" + "\n".join(summary_lines)
        return ExpenseResult(success=True, message=msg, expenses=all_expenses, total=total)

    return ExpenseResult(success=False, message=f"Unknown action: {action}")


async def investment_monitor(
    portfolio: str,
    action: str = "status",
) -> PortfolioStatus:
    """Track investment portfolio status and allocation.

    Args:
        portfolio: Name of the portfolio to monitor.
        action: One of "status", "allocation", "performance".
    """
    holdings = await _store.get_portfolio(portfolio)
    if holdings is None:
        return PortfolioStatus(
            portfolio=portfolio,
            total_value=0.0,
            total_cost=0.0,
            total_gain_loss=0.0,
            total_gain_loss_pct=0.0,
            holdings=[],
        )

    for h in holdings:
        h.gain_loss = (h.current_price - h.cost_basis) * h.quantity
        h.gain_loss_pct = ((h.current_price / h.cost_basis) - 1) * 100 if h.cost_basis else 0.0

    total_value = sum(h.current_price * h.quantity for h in holdings)
    total_cost = sum(h.cost_basis * h.quantity for h in holdings)
    total_gl = total_value - total_cost
    total_gl_pct = ((total_value / total_cost) - 1) * 100 if total_cost else 0.0

    return PortfolioStatus(
        portfolio=portfolio,
        total_value=round(total_value, 2),
        total_cost=round(total_cost, 2),
        total_gain_loss=round(total_gl, 2),
        total_gain_loss_pct=round(total_gl_pct, 2),
        holdings=holdings,
    )


async def budget_alert(
    category: str,
    threshold: float,
    period: str = "monthly",
) -> AlertConfig:
    """Set or update a budget alert for a spending category.

    Args:
        category: Expense category to monitor.
        threshold: Spending limit in {{DEFAULT_CURRENCY}} for the period.
        period: One of "daily", "weekly", "monthly", "quarterly", "yearly".
    """
    cat = ExpenseCategory(category.lower())
    bp = BudgetPeriod(period.lower())

    expenses = await _store.list_expenses(category=cat)
    current_spend = sum(e.amount for e in expenses)

    alert = AlertConfig(
        category=cat,
        threshold=threshold,
        period=bp,
        current_spend=round(current_spend, 2),
        remaining=round(max(threshold - current_spend, 0.0), 2),
    )
    await _store.save_alert(alert)
    return alert


async def receipt_scanner(
    image_description: str,
) -> ReceiptData:
    """Extract structured data from a receipt image description.

    In production, pipe the actual image through an OCR/vision model.
    This implementation parses the text description provided by the LLM
    after it has viewed the receipt image.

    Args:
        image_description: Text description or OCR output of the receipt.
    """
    lines = image_description.strip().split("\n")
    merchant = lines[0].strip() if lines else "Unknown"

    line_items: list[ReceiptLineItem] = []
    total = 0.0
    tax = 0.0
    receipt_date = None

    for line in lines[1:]:
        lower = line.lower().strip()
        if lower.startswith("date:"):
            try:
                receipt_date = date.fromisoformat(lower.replace("date:", "").strip())
            except ValueError:
                pass
        elif lower.startswith("tax:"):
            try:
                tax = float(lower.replace("tax:", "").replace("$", "").strip())
            except ValueError:
                pass
        elif lower.startswith("total:"):
            try:
                total = float(lower.replace("total:", "").replace("$", "").strip())
            except ValueError:
                pass
        elif "$" in line or any(c.isdigit() for c in line):
            parts = line.rsplit("$", 1)
            if len(parts) == 2:
                try:
                    price = float(parts[1].strip())
                    line_items.append(ReceiptLineItem(
                        description=parts[0].strip(),
                        unit_price=price,
                        total=price,
                    ))
                except ValueError:
                    pass

    if total == 0.0 and line_items:
        total = sum(item.total for item in line_items) + tax

    subtotal = total - tax if tax else None

    return ReceiptData(
        merchant=merchant,
        date=receipt_date,
        subtotal=round(subtotal, 2) if subtotal is not None else None,
        tax=round(tax, 2) if tax else None,
        total=round(total, 2),
        line_items=line_items,
        confidence=0.7,
    )


# ---------------------------------------------------------------------------
# Tool registry for agent integration
# ---------------------------------------------------------------------------

FINANCE_TOOLS: list[dict[str, Any]] = [
    {
        "name": "expense_tracker",
        "description": "Create, read, update, delete, list, or summarize expense records.",
        "parameters": {
            "type": "object",
            "properties": {
                "action": {"type": "string", "enum": ["create", "read", "update", "delete", "list", "summary"]},
                "amount": {"type": "number", "description": "Amount in {{DEFAULT_CURRENCY}}"},
                "category": {"type": "string", "enum": [c.value for c in ExpenseCategory]},
                "description": {"type": "string"},
                "expense_id": {"type": "string"},
                "merchant": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}},
            },
            "required": ["action"],
        },
        "handler": expense_tracker,
    },
    {
        "name": "investment_monitor",
        "description": "Check portfolio status, allocation, and performance.",
        "parameters": {
            "type": "object",
            "properties": {
                "portfolio": {"type": "string", "description": "Portfolio name"},
                "action": {"type": "string", "enum": ["status", "allocation", "performance"]},
            },
            "required": ["portfolio"],
        },
        "handler": investment_monitor,
    },
    {
        "name": "budget_alert",
        "description": "Set a budget threshold alert for a spending category.",
        "parameters": {
            "type": "object",
            "properties": {
                "category": {"type": "string", "enum": [c.value for c in ExpenseCategory]},
                "threshold": {"type": "number", "description": "Spending limit"},
                "period": {"type": "string", "enum": [p.value for p in BudgetPeriod]},
            },
            "required": ["category", "threshold"],
        },
        "handler": budget_alert,
    },
    {
        "name": "receipt_scanner",
        "description": "Extract structured data from a receipt description.",
        "parameters": {
            "type": "object",
            "properties": {
                "image_description": {"type": "string", "description": "Receipt text or OCR output"},
            },
            "required": ["image_description"],
        },
        "handler": receipt_scanner,
    },
]
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the assistant project |
| `{{DEFAULT_CURRENCY}}` | Default currency code (e.g., USD, EUR) |
| `{{STORAGE_BACKEND}}` | Storage backend (sqlite, postgres, memory) |

## Dependencies

```
pydantic>=2.0.0
```
