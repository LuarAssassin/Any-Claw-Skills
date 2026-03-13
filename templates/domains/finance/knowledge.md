# Domain Knowledge: Finance

Reference knowledge for the finance domain assistant. Injected as context
or used by tools for categorization and validation.

## Expense Categories

| Category | Description | Examples |
|---|---|---|
| Housing | Shelter costs | Rent, mortgage, repairs, property tax |
| Transportation | Getting around | Gas, car payment, transit pass, parking |
| Food | Eating and drinking | Groceries, dining out, coffee, delivery |
| Utilities | Home services | Electric, water, gas, internet, phone |
| Healthcare | Medical costs | Doctor visits, prescriptions, dental |
| Insurance | Coverage premiums | Health, auto, renter, life insurance |
| Entertainment | Leisure spending | Streaming, concerts, games, hobbies |
| Clothing | Apparel | Clothes, shoes, accessories |
| Education | Learning | Tuition, books, courses, certifications |
| Savings | Money set aside | Emergency fund, retirement, investments |
| Personal | Self-care | Haircuts, gym, toiletries |
| Debt | Repayment | Student loans, credit card payments |
| Gifts | Generosity | Birthday gifts, donations, tips |
| Other | Uncategorized | Anything that does not fit above |

## Budget Methods

### 50/30/20 Rule
- 50% Needs: housing, food, utilities, transportation, insurance, healthcare
- 30% Wants: entertainment, clothing, dining out, hobbies
- 20% Savings: emergency fund, retirement, debt repayment above minimums

### Zero-Based Budgeting
Every dollar of income is assigned a purpose. Income minus all allocations
equals zero. Forces intentional decisions about every spending category.

### Envelope Method
Allocate cash (or virtual envelopes) to each category at the start of the
period. When an envelope is empty, spending in that category stops until
the next period.

### Pay Yourself First
Automatically move a fixed percentage to savings and investments before
allocating to any spending categories. Remaining income covers expenses.

## Investment Basics

### Common Asset Classes
- **Equities (stocks)**: ownership shares in companies; higher risk, higher potential return
- **Fixed income (bonds)**: loans to governments or corporations; lower risk, steady income
- **Cash equivalents**: savings accounts, money market funds, CDs; lowest risk, lowest return
- **Real estate**: property or REITs; moderate risk, potential income and appreciation
- **Commodities**: gold, oil, agricultural products; hedge against inflation

### Key Metrics
- **Cost basis**: original purchase price per share
- **Unrealized gain/loss**: current value minus cost basis (not yet sold)
- **Realized gain/loss**: actual profit or loss from a completed sale
- **Allocation**: percentage of portfolio in each asset class
- **Diversification**: spreading investments to reduce risk

### Risk Disclaimer
Past performance does not guarantee future results. All investments carry
risk including potential loss of principal. The assistant does not recommend
specific securities or investment strategies.

## Tax Considerations

### Record-Keeping
- Keep receipts for business expenses, charitable donations, and medical costs
- Track cost basis for all investment purchases
- Maintain records for at least 3-7 years depending on jurisdiction

### Common Deductible Categories (Varies by Jurisdiction)
- Charitable contributions
- Medical expenses above threshold
- Home mortgage interest
- State and local taxes (up to limits)
- Business expenses (if self-employed)
- Education credits

### Important Reminder
Tax laws vary by country, state, and individual situation. The assistant
provides categorization and record-keeping support only. Always consult a
qualified tax professional for filing guidance and tax planning.

## Currency Formatting

| Currency | Code | Symbol | Decimal Places |
|---|---|---|---|
| US Dollar | USD | $ | 2 |
| Euro | EUR | E | 2 |
| British Pound | GBP | L | 2 |
| Japanese Yen | JPY | Y | 0 |
| Chinese Yuan | CNY | Y | 2 |
| Canadian Dollar | CAD | $ | 2 |
| Australian Dollar | AUD | $ | 2 |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{DEFAULT_CURRENCY}}` | Default currency for the project |
| `{{TAX_JURISDICTION}}` | User's tax jurisdiction (e.g., US, UK, EU) |
