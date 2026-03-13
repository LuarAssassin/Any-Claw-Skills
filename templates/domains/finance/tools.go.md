# Domain Tools: Finance (Go)

Template for finance domain tool implementations in Go with strongly typed models.

## Generated File: `tools/finance.go`

```go
// Package tools provides finance domain tools for {{PROJECT_NAME}}.
package tools

import (
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type ExpenseCategory string

const (
	CatHousing        ExpenseCategory = "housing"
	CatTransportation ExpenseCategory = "transportation"
	CatFood           ExpenseCategory = "food"
	CatUtilities      ExpenseCategory = "utilities"
	CatHealthcare     ExpenseCategory = "healthcare"
	CatInsurance      ExpenseCategory = "insurance"
	CatEntertainment  ExpenseCategory = "entertainment"
	CatClothing       ExpenseCategory = "clothing"
	CatEducation      ExpenseCategory = "education"
	CatSavings        ExpenseCategory = "savings"
	CatPersonal       ExpenseCategory = "personal"
	CatDebt           ExpenseCategory = "debt"
	CatGifts          ExpenseCategory = "gifts"
	CatOther          ExpenseCategory = "other"
)

type BudgetPeriod string

const (
	PeriodDaily     BudgetPeriod = "daily"
	PeriodWeekly    BudgetPeriod = "weekly"
	PeriodMonthly   BudgetPeriod = "monthly"
	PeriodQuarterly BudgetPeriod = "quarterly"
	PeriodYearly    BudgetPeriod = "yearly"
)

type Expense struct {
	ID          string          `json:"id"`
	Amount      float64         `json:"amount"`
	Category    ExpenseCategory `json:"category"`
	Description string          `json:"description"`
	Date        string          `json:"date"`
	Merchant    string          `json:"merchant,omitempty"`
	Tags        []string        `json:"tags,omitempty"`
	CreatedAt   time.Time       `json:"created_at"`
}

type ExpenseResult struct {
	Success  bool      `json:"success"`
	Message  string    `json:"message"`
	Expense  *Expense  `json:"expense,omitempty"`
	Expenses []Expense `json:"expenses,omitempty"`
	Total    *float64  `json:"total,omitempty"`
}

type PortfolioHolding struct {
	Symbol       string  `json:"symbol"`
	Name         string  `json:"name"`
	Quantity     float64 `json:"quantity"`
	CostBasis    float64 `json:"cost_basis"`
	CurrentPrice float64 `json:"current_price"`
	GainLoss     float64 `json:"gain_loss"`
	GainLossPct  float64 `json:"gain_loss_pct"`
}

type PortfolioStatus struct {
	Portfolio       string             `json:"portfolio"`
	TotalValue      float64            `json:"total_value"`
	TotalCost       float64            `json:"total_cost"`
	TotalGainLoss   float64            `json:"total_gain_loss"`
	TotalGainLossPct float64           `json:"total_gain_loss_pct"`
	Holdings        []PortfolioHolding `json:"holdings"`
	LastUpdated     time.Time          `json:"last_updated"`
	Currency        string             `json:"currency"`
}

type AlertConfig struct {
	ID           string          `json:"id"`
	Category     ExpenseCategory `json:"category"`
	Threshold    float64         `json:"threshold"`
	Period       BudgetPeriod    `json:"period"`
	CurrentSpend float64         `json:"current_spend"`
	Remaining    float64         `json:"remaining"`
	IsActive     bool            `json:"is_active"`
	CreatedAt    time.Time       `json:"created_at"`
}

type ReceiptLineItem struct {
	Description string  `json:"description"`
	Quantity    int     `json:"quantity"`
	UnitPrice   float64 `json:"unit_price"`
	Total       float64 `json:"total"`
}

type ReceiptData struct {
	Merchant      string            `json:"merchant"`
	Date          string            `json:"date,omitempty"`
	Subtotal      *float64          `json:"subtotal,omitempty"`
	Tax           *float64          `json:"tax,omitempty"`
	Total         float64           `json:"total"`
	Currency      string            `json:"currency"`
	LineItems     []ReceiptLineItem `json:"line_items,omitempty"`
	PaymentMethod string            `json:"payment_method,omitempty"`
	Confidence    float64           `json:"confidence"`
}

// ---------------------------------------------------------------------------
// Storage (replace with {{STORAGE_BACKEND}} in production)
// ---------------------------------------------------------------------------

type FinanceStore struct {
	mu         sync.RWMutex
	expenses   map[string]Expense
	alerts     map[string]AlertConfig
	portfolios map[string][]PortfolioHolding
}

func NewFinanceStore() *FinanceStore {
	return &FinanceStore{
		expenses:   make(map[string]Expense),
		alerts:     make(map[string]AlertConfig),
		portfolios: make(map[string][]PortfolioHolding),
	}
}

var defaultStore = NewFinanceStore()

// ---------------------------------------------------------------------------
// Tool implementations
// ---------------------------------------------------------------------------

func round2(v float64) float64 {
	return math.Round(v*100) / 100
}

func shortID() string {
	return uuid.New().String()[:12]
}

// ExpenseTracker handles CRUD operations on expense records.
func ExpenseTracker(action string, amount float64, category, description string, expenseID, merchant string, tags []string) ExpenseResult {
	cat := ExpenseCategory(strings.ToLower(category))
	if cat == "" {
		cat = CatOther
	}

	switch action {
	case "create":
		exp := Expense{
			ID:          shortID(),
			Amount:      amount,
			Category:    cat,
			Description: description,
			Date:        time.Now().Format("2006-01-02"),
			Merchant:    merchant,
			Tags:        tags,
			CreatedAt:   time.Now().UTC(),
		}
		defaultStore.mu.Lock()
		defaultStore.expenses[exp.ID] = exp
		defaultStore.mu.Unlock()
		return ExpenseResult{
			Success: true,
			Message: fmt.Sprintf("Recorded %.2f expense", amount),
			Expense: &exp,
		}

	case "read":
		if expenseID == "" {
			return ExpenseResult{Success: false, Message: "expense_id is required for read"}
		}
		defaultStore.mu.RLock()
		exp, ok := defaultStore.expenses[expenseID]
		defaultStore.mu.RUnlock()
		if !ok {
			return ExpenseResult{Success: false, Message: fmt.Sprintf("Expense %s not found", expenseID)}
		}
		return ExpenseResult{Success: true, Message: "Found", Expense: &exp}

	case "update":
		if expenseID == "" {
			return ExpenseResult{Success: false, Message: "expense_id is required for update"}
		}
		defaultStore.mu.Lock()
		existing, ok := defaultStore.expenses[expenseID]
		if !ok {
			defaultStore.mu.Unlock()
			return ExpenseResult{Success: false, Message: fmt.Sprintf("Expense %s not found", expenseID)}
		}
		if amount > 0 {
			existing.Amount = amount
		}
		if category != "" {
			existing.Category = cat
		}
		if description != "" {
			existing.Description = description
		}
		if merchant != "" {
			existing.Merchant = merchant
		}
		if len(tags) > 0 {
			existing.Tags = tags
		}
		defaultStore.expenses[expenseID] = existing
		defaultStore.mu.Unlock()
		return ExpenseResult{Success: true, Message: "Updated", Expense: &existing}

	case "delete":
		if expenseID == "" {
			return ExpenseResult{Success: false, Message: "expense_id is required for delete"}
		}
		defaultStore.mu.Lock()
		_, ok := defaultStore.expenses[expenseID]
		if ok {
			delete(defaultStore.expenses, expenseID)
		}
		defaultStore.mu.Unlock()
		if !ok {
			return ExpenseResult{Success: false, Message: fmt.Sprintf("Expense %s not found", expenseID)}
		}
		return ExpenseResult{Success: true, Message: "Deleted"}

	case "list":
		defaultStore.mu.RLock()
		var results []Expense
		for _, e := range defaultStore.expenses {
			if cat != CatOther && e.Category != cat {
				continue
			}
			results = append(results, e)
		}
		defaultStore.mu.RUnlock()
		sort.Slice(results, func(i, j int) bool { return results[i].Date > results[j].Date })
		total := 0.0
		for _, e := range results {
			total += e.Amount
		}
		t := round2(total)
		return ExpenseResult{
			Success:  true,
			Message:  fmt.Sprintf("Found %d expenses", len(results)),
			Expenses: results,
			Total:    &t,
		}

	case "summary":
		defaultStore.mu.RLock()
		byCat := make(map[ExpenseCategory]float64)
		var all []Expense
		for _, e := range defaultStore.expenses {
			byCat[e.Category] += e.Amount
			all = append(all, e)
		}
		defaultStore.mu.RUnlock()
		total := 0.0
		var lines []string
		for k, v := range byCat {
			total += v
			lines = append(lines, fmt.Sprintf("  %s: %.2f", k, v))
		}
		sort.Strings(lines)
		t := round2(total)
		msg := fmt.Sprintf("Total: %.2f\n%s", total, strings.Join(lines, "\n"))
		return ExpenseResult{Success: true, Message: msg, Expenses: all, Total: &t}

	default:
		return ExpenseResult{Success: false, Message: fmt.Sprintf("Unknown action: %s", action)}
	}
}

// InvestmentMonitor returns the current status of a named portfolio.
func InvestmentMonitor(portfolio, action string) PortfolioStatus {
	defaultStore.mu.RLock()
	holdings, ok := defaultStore.portfolios[portfolio]
	defaultStore.mu.RUnlock()

	if !ok || len(holdings) == 0 {
		return PortfolioStatus{
			Portfolio:   portfolio,
			Holdings:    []PortfolioHolding{},
			LastUpdated: time.Now().UTC(),
			Currency:    "{{DEFAULT_CURRENCY}}",
		}
	}

	var totalValue, totalCost float64
	for i := range holdings {
		h := &holdings[i]
		h.GainLoss = (h.CurrentPrice - h.CostBasis) * h.Quantity
		if h.CostBasis > 0 {
			h.GainLossPct = ((h.CurrentPrice / h.CostBasis) - 1) * 100
		}
		totalValue += h.CurrentPrice * h.Quantity
		totalCost += h.CostBasis * h.Quantity
	}

	gl := totalValue - totalCost
	glPct := 0.0
	if totalCost > 0 {
		glPct = ((totalValue / totalCost) - 1) * 100
	}

	return PortfolioStatus{
		Portfolio:        portfolio,
		TotalValue:       round2(totalValue),
		TotalCost:        round2(totalCost),
		TotalGainLoss:    round2(gl),
		TotalGainLossPct: round2(glPct),
		Holdings:         holdings,
		LastUpdated:      time.Now().UTC(),
		Currency:         "{{DEFAULT_CURRENCY}}",
	}
}

// BudgetAlert creates a spending threshold alert for a category.
func BudgetAlert(category string, threshold float64, period string) AlertConfig {
	cat := ExpenseCategory(strings.ToLower(category))
	bp := BudgetPeriod(strings.ToLower(period))
	if bp == "" {
		bp = PeriodMonthly
	}

	defaultStore.mu.RLock()
	var currentSpend float64
	for _, e := range defaultStore.expenses {
		if e.Category == cat {
			currentSpend += e.Amount
		}
	}
	defaultStore.mu.RUnlock()

	remaining := math.Max(threshold-currentSpend, 0)

	alert := AlertConfig{
		ID:           shortID(),
		Category:     cat,
		Threshold:    threshold,
		Period:       bp,
		CurrentSpend: round2(currentSpend),
		Remaining:    round2(remaining),
		IsActive:     true,
		CreatedAt:    time.Now().UTC(),
	}

	defaultStore.mu.Lock()
	defaultStore.alerts[alert.ID] = alert
	defaultStore.mu.Unlock()

	return alert
}

// ReceiptScanner parses a receipt text description into structured data.
func ReceiptScanner(imageDescription string) ReceiptData {
	lines := strings.Split(strings.TrimSpace(imageDescription), "\n")
	merchant := "Unknown"
	if len(lines) > 0 {
		merchant = strings.TrimSpace(lines[0])
	}

	var lineItems []ReceiptLineItem
	var total, tax float64
	var receiptDate string

	for _, line := range lines[1:] {
		lower := strings.ToLower(strings.TrimSpace(line))

		if strings.HasPrefix(lower, "date:") {
			receiptDate = strings.TrimSpace(strings.TrimPrefix(lower, "date:"))
		} else if strings.HasPrefix(lower, "tax:") {
			v, err := strconv.ParseFloat(strings.TrimSpace(strings.Replace(strings.TrimPrefix(lower, "tax:"), "$", "", 1)), 64)
			if err == nil {
				tax = v
			}
		} else if strings.HasPrefix(lower, "total:") {
			v, err := strconv.ParseFloat(strings.TrimSpace(strings.Replace(strings.TrimPrefix(lower, "total:"), "$", "", 1)), 64)
			if err == nil {
				total = v
			}
		} else if strings.Contains(line, "$") {
			parts := strings.SplitN(line, "$", 2)
			if len(parts) == 2 {
				price, err := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
				if err == nil {
					lineItems = append(lineItems, ReceiptLineItem{
						Description: strings.TrimSpace(parts[0]),
						Quantity:    1,
						UnitPrice:   price,
						Total:       price,
					})
				}
			}
		}
	}

	if total == 0 && len(lineItems) > 0 {
		for _, item := range lineItems {
			total += item.Total
		}
		total += tax
	}

	result := ReceiptData{
		Merchant:   merchant,
		Date:       receiptDate,
		Total:      round2(total),
		Currency:   "{{DEFAULT_CURRENCY}}",
		LineItems:  lineItems,
		Confidence: 0.7,
	}

	if tax > 0 {
		t := round2(tax)
		result.Tax = &t
		sub := round2(total - tax)
		result.Subtotal = &sub
	}

	return result
}

// ---------------------------------------------------------------------------
// Tool registry for agent integration
// ---------------------------------------------------------------------------

type ToolDef struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Parameters  json.RawMessage `json:"parameters"`
}

func FinanceToolDefs() []ToolDef {
	return []ToolDef{
		{
			Name:        "expense_tracker",
			Description: "Create, read, update, delete, list, or summarize expense records.",
			Parameters:  json.RawMessage(`{"type":"object","properties":{"action":{"type":"string","enum":["create","read","update","delete","list","summary"]},"amount":{"type":"number"},"category":{"type":"string"},"description":{"type":"string"},"expense_id":{"type":"string"},"merchant":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["action"]}`),
		},
		{
			Name:        "investment_monitor",
			Description: "Check portfolio status, allocation, and performance.",
			Parameters:  json.RawMessage(`{"type":"object","properties":{"portfolio":{"type":"string"},"action":{"type":"string","enum":["status","allocation","performance"]}},"required":["portfolio"]}`),
		},
		{
			Name:        "budget_alert",
			Description: "Set a budget threshold alert for a spending category.",
			Parameters:  json.RawMessage(`{"type":"object","properties":{"category":{"type":"string"},"threshold":{"type":"number"},"period":{"type":"string","enum":["daily","weekly","monthly","quarterly","yearly"]}},"required":["category","threshold"]}`),
		},
		{
			Name:        "receipt_scanner",
			Description: "Extract structured data from a receipt description.",
			Parameters:  json.RawMessage(`{"type":"object","properties":{"image_description":{"type":"string"}},"required":["image_description"]}`),
		},
	}
}
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the assistant project |
| `{{DEFAULT_CURRENCY}}` | Default currency code (e.g., USD, EUR) |
| `{{STORAGE_BACKEND}}` | Storage backend (sqlite, postgres, memory) |

## Dependencies

```
github.com/google/uuid v1.6.0
```
