# Provider: Provider Router (Go)

Template for multi-provider router with fallback chain and cost tracking.

## Generated File: `providers/router.go`

```go
// Package providers implements LLM provider integrations for {{PROJECT_NAME}}.
package providers

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"
)

// CostPerMillion holds input/output cost per 1M tokens in USD.
type CostPerMillion struct {
	Input  float64
	Output float64
}

var costTable = map[string]CostPerMillion{
	"gpt-4o":                      {2.50, 10.00},
	"gpt-4o-mini":                 {0.15, 0.60},
	"gpt-4.1":                     {2.00, 8.00},
	"gpt-4.1-mini":                {0.40, 1.60},
	"claude-sonnet-4-20250514":    {3.00, 15.00},
	"claude-haiku-35-20241022":    {0.80, 4.00},
	"claude-opus-4-20250514":      {15.00, 75.00},
}

// UsageRecord tracks a single API call.
type UsageRecord struct {
	Provider         string
	Model            string
	PromptTokens     int
	CompletionTokens int
	CostUSD          float64
	LatencyMs        float64
	Timestamp        time.Time
}

// ProviderConfig defines a provider with its supported models and priority.
type ProviderConfig struct {
	Name     string
	Provider Provider
	Models   []string
	Priority int
}

// UsageSummary holds aggregated usage stats.
type UsageSummary struct {
	TotalCostUSD  float64
	TotalRequests int
	ByProvider    map[string]ProviderStats
}

// ProviderStats holds per-provider usage stats.
type ProviderStats struct {
	Requests     int
	TotalTokens  int
	CostUSD      float64
	AvgLatencyMs float64
}

// ProviderRouter routes requests to providers with fallback and cost tracking.
type ProviderRouter struct {
	configs  []ProviderConfig
	modelMap map[string]*ProviderConfig
	mu       sync.Mutex
	usage    []UsageRecord
}

// NewProviderRouter creates a router from provider configs sorted by priority.
func NewProviderRouter(configs []ProviderConfig) *ProviderRouter {
	// Sort by priority (simple insertion sort for small slices).
	sorted := make([]ProviderConfig, len(configs))
	copy(sorted, configs)
	for i := 1; i < len(sorted); i++ {
		for j := i; j > 0 && sorted[j].Priority < sorted[j-1].Priority; j-- {
			sorted[j], sorted[j-1] = sorted[j-1], sorted[j]
		}
	}

	modelMap := make(map[string]*ProviderConfig)
	for i := range sorted {
		for _, model := range sorted[i].Models {
			modelMap[model] = &sorted[i]
		}
	}

	return &ProviderRouter{
		configs:  sorted,
		modelMap: modelMap,
	}
}

func (r *ProviderRouter) resolve(model string) []*ProviderConfig {
	if model != "" {
		if primary, ok := r.modelMap[model]; ok {
			result := []*ProviderConfig{primary}
			for i := range r.configs {
				if &r.configs[i] != primary {
					result = append(result, &r.configs[i])
				}
			}
			return result
		}
	}
	result := make([]*ProviderConfig, len(r.configs))
	for i := range r.configs {
		result[i] = &r.configs[i]
	}
	return result
}

func computeCost(model string, prompt, completion int) float64 {
	rates, ok := costTable[model]
	if !ok {
		return 0
	}
	return (float64(prompt)*rates.Input + float64(completion)*rates.Output) / 1_000_000
}

// Chat routes a request through the fallback chain.
func (r *ProviderRouter) Chat(ctx context.Context, messages []Message, opts ChatOptions) (Response, error) {
	chain := r.resolve(opts.Model)
	var lastErr error

	for _, cfg := range chain {
		start := time.Now()
		resp, err := cfg.Provider.Chat(ctx, messages, opts)
		elapsed := float64(time.Since(start).Milliseconds())

		if err != nil {
			lastErr = err
			log.Printf("Provider %s failed: %v. Trying next.", cfg.Name, err)
			continue
		}

		cost := computeCost(resp.Model, resp.Usage.PromptTokens, resp.Usage.CompletionTokens)
		r.mu.Lock()
		r.usage = append(r.usage, UsageRecord{
			Provider:         cfg.Name,
			Model:            resp.Model,
			PromptTokens:     resp.Usage.PromptTokens,
			CompletionTokens: resp.Usage.CompletionTokens,
			CostUSD:          cost,
			LatencyMs:        elapsed,
			Timestamp:        time.Now(),
		})
		r.mu.Unlock()
		return resp, nil
	}
	return Response{}, fmt.Errorf("all providers failed, last error: %w", lastErr)
}

// ChatStream routes a streaming request through the fallback chain.
func (r *ProviderRouter) ChatStream(ctx context.Context, messages []Message, opts ChatOptions) (<-chan string, <-chan error) {
	chain := r.resolve(opts.Model)
	for _, cfg := range chain {
		chunks, errc := cfg.Provider.ChatStream(ctx, messages, opts)
		// Read first chunk to verify the stream works.
		first, ok := <-chunks
		if !ok {
			// Channel closed immediately; check for error.
			if err := <-errc; err != nil {
				log.Printf("Provider %s stream failed: %v. Trying next.", cfg.Name, err)
				continue
			}
		}
		// Re-wrap with the first chunk prepended.
		out := make(chan string, 64)
		outErr := make(chan error, 1)
		go func() {
			defer close(out)
			defer close(outErr)
			out <- first
			for c := range chunks {
				out <- c
			}
			if err := <-errc; err != nil {
				outErr <- err
			}
		}()
		return out, outErr
	}
	errc := make(chan error, 1)
	errc <- fmt.Errorf("all providers failed for streaming")
	close(errc)
	ch := make(chan string)
	close(ch)
	return ch, errc
}

// GetTotalCost returns the total cost across all usage.
func (r *ProviderRouter) GetTotalCost() float64 {
	r.mu.Lock()
	defer r.mu.Unlock()
	var total float64
	for _, u := range r.usage {
		total += u.CostUSD
	}
	return total
}

// GetUsageSummary returns aggregated usage statistics.
func (r *ProviderRouter) GetUsageSummary() UsageSummary {
	r.mu.Lock()
	defer r.mu.Unlock()

	byProvider := make(map[string]ProviderStats)
	for _, u := range r.usage {
		stats := byProvider[u.Provider]
		stats.Requests++
		stats.TotalTokens += u.PromptTokens + u.CompletionTokens
		stats.CostUSD += u.CostUSD
		byProvider[u.Provider] = stats
	}
	for name, stats := range byProvider {
		var totalLatency float64
		var count int
		for _, u := range r.usage {
			if u.Provider == name {
				totalLatency += u.LatencyMs
				count++
			}
		}
		if count > 0 {
			stats.AvgLatencyMs = totalLatency / float64(count)
		}
		byProvider[name] = stats
	}

	var totalCost float64
	for _, u := range r.usage {
		totalCost += u.CostUSD
	}
	return UsageSummary{
		TotalCostUSD:  totalCost,
		TotalRequests: len(r.usage),
		ByProvider:    byProvider,
	}
}
```

## Configuration

| Env Variable | Required | Description |
|---|---|---|
| `LLM_DEFAULT_PROVIDER` | No | Default provider name to route to |
| `LLM_FALLBACK_ENABLED` | No | Enable fallback chain (default: `true`) |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | Go module path |

## Usage Example

```go
router := NewProviderRouter([]ProviderConfig{
    {
        Name:     "anthropic",
        Provider: NewAnthropicProvider("claude-sonnet-4-20250514"),
        Models:   []string{"claude-sonnet-4-20250514", "claude-haiku-35-20241022"},
        Priority: 0,
    },
    {
        Name:     "openai",
        Provider: NewOpenAIProvider("gpt-4o"),
        Models:   []string{"gpt-4o", "gpt-4o-mini"},
        Priority: 1,
    },
})

resp, err := router.Chat(ctx, messages, ChatOptions{Model: "claude-sonnet-4-20250514"})
fmt.Printf("Cost so far: $%.6f\n", router.GetTotalCost())
```

## Dependencies

No external dependencies. Uses Go standard library only.
