# Provider: Anthropic (Go)

Template for Anthropic LLM provider integration using net/http (no SDK).

## Generated File: `providers/anthropic.go`

```go
// Package providers implements LLM provider integrations for {{PROJECT_NAME}}.
package providers

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"strings"
	"time"
)

// AnthropicProvider implements the Provider interface for Anthropic.
type AnthropicProvider struct {
	APIKey     string
	Model      string
	MaxTokens  int
	MaxRetries int
	HTTPClient *http.Client
}

// NewAnthropicProvider creates a new Anthropic provider.
func NewAnthropicProvider(model string) *AnthropicProvider {
	if model == "" {
		model = "claude-sonnet-4-20250514"
	}
	return &AnthropicProvider{
		APIKey:     os.Getenv("ANTHROPIC_API_KEY"),
		Model:      model,
		MaxTokens:  4096,
		MaxRetries: 3,
		HTTPClient: &http.Client{Timeout: 60 * time.Second},
	}
}

type anthropicRequest struct {
	Model     string              `json:"model"`
	MaxTokens int                 `json:"max_tokens"`
	System    string              `json:"system,omitempty"`
	Messages  []anthropicMessage  `json:"messages"`
	Tools     []anthropicTool     `json:"tools,omitempty"`
	Stream    bool                `json:"stream,omitempty"`
}

type anthropicMessage struct {
	Role    string `json:"role"`
	Content any    `json:"content"`
}

type anthropicTool struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	InputSchema map[string]any `json:"input_schema"`
}

type anthropicResponse struct {
	Content    []anthropicBlock `json:"content"`
	Usage      anthropicUsage   `json:"usage"`
	Model      string           `json:"model"`
	StopReason string           `json:"stop_reason"`
}

type anthropicBlock struct {
	Type  string         `json:"type"`
	Text  string         `json:"text,omitempty"`
	ID    string         `json:"id,omitempty"`
	Name  string         `json:"name,omitempty"`
	Input map[string]any `json:"input,omitempty"`
}

type anthropicUsage struct {
	InputTokens  int `json:"input_tokens"`
	OutputTokens int `json:"output_tokens"`
}

type anthropicStreamEvent struct {
	Type  string `json:"type"`
	Delta struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"delta,omitempty"`
}

func (p *AnthropicProvider) formatMessages(messages []Message) (string, []anthropicMessage) {
	var system string
	var formatted []anthropicMessage

	for _, m := range messages {
		if m.Role == "system" {
			system = m.Content
			continue
		}
		if m.Role == "tool" {
			formatted = append(formatted, anthropicMessage{
				Role: "user",
				Content: []map[string]any{
					{
						"type":        "tool_result",
						"tool_use_id": m.ToolCallID,
						"content":     m.Content,
					},
				},
			})
			continue
		}
		if len(m.ToolCalls) > 0 {
			var blocks []map[string]any
			if m.Content != "" {
				blocks = append(blocks, map[string]any{"type": "text", "text": m.Content})
			}
			for _, tc := range m.ToolCalls {
				var args map[string]any
				json.Unmarshal([]byte(tc.Function.Arguments), &args)
				blocks = append(blocks, map[string]any{
					"type":  "tool_use",
					"id":    tc.ID,
					"name":  tc.Function.Name,
					"input": args,
				})
			}
			formatted = append(formatted, anthropicMessage{Role: "assistant", Content: blocks})
			continue
		}
		formatted = append(formatted, anthropicMessage{Role: m.Role, Content: m.Content})
	}
	return system, formatted
}

func (p *AnthropicProvider) buildTools(defs []ToolDef) []anthropicTool {
	if len(defs) == 0 {
		return nil
	}
	tools := make([]anthropicTool, len(defs))
	for i, d := range defs {
		tools[i] = anthropicTool{
			Name:        d.Name,
			Description: d.Description,
			InputSchema: d.Parameters,
		}
	}
	return tools
}

func (p *AnthropicProvider) doRequest(ctx context.Context, body []byte) (*http.Response, error) {
	var lastErr error
	for attempt := 0; attempt < p.MaxRetries; attempt++ {
		req, err := http.NewRequestWithContext(ctx, "POST", "https://api.anthropic.com/v1/messages", bytes.NewReader(body))
		if err != nil {
			return nil, fmt.Errorf("create request: %w", err)
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("x-api-key", p.APIKey)
		req.Header.Set("anthropic-version", "2023-06-01")

		resp, err := p.HTTPClient.Do(req)
		if err != nil {
			lastErr = err
			wait := time.Duration(math.Min(float64(1<<attempt), 16)) * time.Second
			time.Sleep(wait)
			continue
		}
		if resp.StatusCode == 429 || resp.StatusCode >= 500 {
			resp.Body.Close()
			lastErr = fmt.Errorf("HTTP %d", resp.StatusCode)
			wait := time.Duration(math.Min(float64(1<<attempt), 16)) * time.Second
			time.Sleep(wait)
			continue
		}
		if resp.StatusCode != 200 {
			respBody, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			return nil, fmt.Errorf("Anthropic API error %d: %s", resp.StatusCode, string(respBody))
		}
		return resp, nil
	}
	return nil, fmt.Errorf("max retries exceeded: %w", lastErr)
}

// Chat sends a non-streaming message to Anthropic.
func (p *AnthropicProvider) Chat(ctx context.Context, messages []Message, opts ChatOptions) (Response, error) {
	model := opts.Model
	if model == "" {
		model = p.Model
	}
	maxTokens := opts.MaxTokens
	if maxTokens == 0 {
		maxTokens = p.MaxTokens
	}

	system, formatted := p.formatMessages(messages)
	reqBody := anthropicRequest{
		Model:     model,
		MaxTokens: maxTokens,
		System:    system,
		Messages:  formatted,
		Tools:     p.buildTools(opts.Tools),
		Stream:    false,
	}
	body, err := json.Marshal(reqBody)
	if err != nil {
		return Response{}, fmt.Errorf("marshal request: %w", err)
	}

	resp, err := p.doRequest(ctx, body)
	if err != nil {
		return Response{}, err
	}
	defer resp.Body.Close()

	var result anthropicResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return Response{}, fmt.Errorf("decode response: %w", err)
	}

	var content string
	var toolCalls []ToolCall
	for _, block := range result.Content {
		switch block.Type {
		case "text":
			content += block.Text
		case "tool_use":
			args, _ := json.Marshal(block.Input)
			toolCalls = append(toolCalls, ToolCall{
				ID: block.ID,
				Function: FunctionCall{
					Name:      block.Name,
					Arguments: string(args),
				},
			})
		}
	}

	return Response{
		Content:   content,
		ToolCalls: toolCalls,
		Usage: Usage{
			PromptTokens:     result.Usage.InputTokens,
			CompletionTokens: result.Usage.OutputTokens,
			TotalTokens:      result.Usage.InputTokens + result.Usage.OutputTokens,
		},
		Model:        result.Model,
		FinishReason: result.StopReason,
	}, nil
}

// ChatStream sends a streaming message to Anthropic.
func (p *AnthropicProvider) ChatStream(ctx context.Context, messages []Message, opts ChatOptions) (<-chan string, <-chan error) {
	chunks := make(chan string, 64)
	errc := make(chan error, 1)

	go func() {
		defer close(chunks)
		defer close(errc)

		model := opts.Model
		if model == "" {
			model = p.Model
		}
		maxTokens := opts.MaxTokens
		if maxTokens == 0 {
			maxTokens = p.MaxTokens
		}

		system, formatted := p.formatMessages(messages)
		reqBody := anthropicRequest{
			Model:     model,
			MaxTokens: maxTokens,
			System:    system,
			Messages:  formatted,
			Tools:     p.buildTools(opts.Tools),
			Stream:    true,
		}
		body, err := json.Marshal(reqBody)
		if err != nil {
			errc <- fmt.Errorf("marshal request: %w", err)
			return
		}

		resp, err := p.doRequest(ctx, body)
		if err != nil {
			errc <- err
			return
		}
		defer resp.Body.Close()

		scanner := bufio.NewScanner(resp.Body)
		for scanner.Scan() {
			line := scanner.Text()
			if !strings.HasPrefix(line, "data: ") {
				continue
			}
			data := strings.TrimPrefix(line, "data: ")
			var event anthropicStreamEvent
			if err := json.Unmarshal([]byte(data), &event); err != nil {
				continue
			}
			if event.Type == "content_block_delta" && event.Delta.Type == "text_delta" && event.Delta.Text != "" {
				chunks <- event.Delta.Text
			}
		}
		if err := scanner.Err(); err != nil {
			errc <- fmt.Errorf("read stream: %w", err)
		}
	}()

	return chunks, errc
}
```

## Configuration

| Env Variable | Required | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | Go module path |

## Dependencies

No external dependencies. Uses Go standard library only.
