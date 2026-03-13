# MCP Server: Finance (Python)

Template for a Model Context Protocol server exposing finance tools via FastMCP.

## Generated File: `mcp_servers/finance_server.py`

```python
"""Finance MCP server for {{PROJECT_NAME}}.

Run with:
    python -m mcp_servers.finance_server
    # or
    uvx fastmcp run mcp_servers/finance_server.py
"""

from datetime import date

from fastmcp import FastMCP

from tools.finance_tools import (
    AlertConfig,
    ExpenseResult,
    PortfolioStatus,
    ReceiptData,
    budget_alert,
    expense_tracker,
    investment_monitor,
    receipt_scanner,
)

mcp = FastMCP(
    "{{PROJECT_NAME}}-finance",
    description="Finance tools: expense tracking, investments, budgets, receipts",
)


# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

@mcp.resource("finance://categories")
def list_categories() -> list[str]:
    """Return all supported expense categories."""
    return [
        "housing", "transportation", "food", "utilities", "healthcare",
        "insurance", "entertainment", "clothing", "education", "savings",
        "personal", "debt", "gifts", "other",
    ]


@mcp.resource("finance://budget-periods")
def list_budget_periods() -> list[str]:
    """Return all supported budget periods."""
    return ["daily", "weekly", "monthly", "quarterly", "yearly"]


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

@mcp.tool()
async def track_expense(
    action: str,
    amount: float = 0.0,
    category: str = "other",
    description: str = "",
    expense_id: str | None = None,
    merchant: str | None = None,
    tags: list[str] | None = None,
) -> ExpenseResult:
    """Create, read, update, delete, list, or summarize expenses.

    Args:
        action: One of create, read, update, delete, list, summary.
        amount: Amount in {{DEFAULT_CURRENCY}} (required for create/update).
        category: Expense category.
        description: Short description.
        expense_id: Required for read/update/delete.
        merchant: Merchant name.
        tags: Tags for filtering.
    """
    return await expense_tracker(
        action=action,
        amount=amount,
        category=category,
        description=description,
        expense_id=expense_id,
        merchant=merchant,
        tags=tags,
    )


@mcp.tool()
async def check_portfolio(
    portfolio: str,
    action: str = "status",
) -> PortfolioStatus:
    """Check investment portfolio status.

    Args:
        portfolio: Portfolio name.
        action: One of status, allocation, performance.
    """
    return await investment_monitor(portfolio=portfolio, action=action)


@mcp.tool()
async def set_budget_alert(
    category: str,
    threshold: float,
    period: str = "monthly",
) -> AlertConfig:
    """Set a spending threshold alert for a category.

    Args:
        category: Expense category to monitor.
        threshold: Spending limit in {{DEFAULT_CURRENCY}}.
        period: One of daily, weekly, monthly, quarterly, yearly.
    """
    return await budget_alert(
        category=category,
        threshold=threshold,
        period=period,
    )


@mcp.tool()
async def scan_receipt(
    image_description: str,
) -> ReceiptData:
    """Extract structured data from a receipt image description.

    Args:
        image_description: Text description or OCR output of the receipt.
    """
    return await receipt_scanner(image_description=image_description)


# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

@mcp.prompt()
def monthly_summary() -> str:
    """Prompt the assistant to generate a monthly expense summary."""
    today = date.today()
    return (
        f"Please generate a summary of my expenses for "
        f"{today.strftime('%B %Y')}. Group by category, show totals, "
        f"and flag any categories where spending exceeds my budget alerts."
    )


@mcp.prompt()
def budget_check() -> str:
    """Prompt the assistant to check all active budget alerts."""
    return (
        "Check all my active budget alerts. For each one, show the category, "
        "threshold, current spend, and remaining amount. Highlight any that "
        "are above 80% of the threshold."
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run()
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the assistant project |
| `{{DEFAULT_CURRENCY}}` | Default currency code (e.g., USD, EUR) |

## Dependencies

```
fastmcp>=2.0.0
```

## MCP Client Configuration

```json
{
  "mcpServers": {
    "{{PROJECT_NAME}}-finance": {
      "command": "python",
      "args": ["-m", "mcp_servers.finance_server"]
    }
  }
}
```
