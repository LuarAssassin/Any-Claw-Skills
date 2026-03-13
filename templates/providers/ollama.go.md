# Provider: Ollama (Go)

Template for Ollama local LLM provider integration using net/http.

## Generated File: `providers/ollama.go`

```go
// Package providers implements LLM provider integrations for {{PROJECT_NAME}}.
package providers

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

// OllamaProvider implements the Provider interface for local Ollama inference.
type OllamaProvider struct {
	BaseURL    string
	Model      string
	HTTPClient *http.Client
}

// NewOllamaProvider creates a new Ollama provider.
func NewOllamaProvider(model string) *OllamaProvider {
	baseURL := os.Getenv("OLLAMA_HOST")
	if baseURL == "" {
		baseURL = "http://localhost:11434"
	}
	if model == "" {
		model = "llama3.1"
	}
	return &OllamaProvider{
		BaseURL:    strings.TrimRight(baseURL, "/"),
		Model:      model,
		HTTPClient: &http.Client{Timeout: 120 * time.Second},
	}
}

type ollamaRequest struct {
	Model    string        `json:"model"`
	Messages []ollamaMsg   `json:"messages"`
	Stream   bool          `json:"stream"`
	Tools    []openaiTool  `json:"tools,omitempty"`
}

type ollamaMsg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ollamaResponse struct {
	Message        ollamaMsgResp   `json:"message"`
	Model          string          `json:"model"`
	DoneReason     string          `json:"done_reason"`
	PromptEvalCount int            `json:"prompt_eval_count"`
	EvalCount      int             `json:"eval_count"`
}

type ollamaMsgResp struct {
	Role      string              `json:"role"`
	Content   string              `json:"content"`
	ToolCalls []ollamaToolCall    `json:"tool_calls,omitempty"`
}

type ollamaToolCall struct {
	Function ollamaFunctionCall `json:"function"`
}

type ollamaFunctionCall struct {
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments"`
}

// OllamaModelInfo holds information about a local model.
type OllamaModelInfo struct {
	Name       string `json:"name"`
	Size       int64  `json:"size"`
	ModifiedAt string `json:"modified_at"`
}

// ListModels returns all locally available models.
func (p *OllamaProvider) ListModels(ctx context.Context) ([]OllamaModelInfo, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", p.BaseURL+"/api/tags", nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	resp, err := p.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("list models: %w", err)
	}
	defer resp.Body.Close()

	var result struct {
		Models []OllamaModelInfo `json:"models"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return result.Models, nil
}

func (p *OllamaProvider) buildTools(defs []ToolDef) []openaiTool {
	if len(defs) == 0 {
		return nil
	}
	tools := make([]openaiTool, len(defs))
	for i, d := range defs {
		tools[i] = openaiTool{
			Type: "function",
			Function: openaiFunction{
				Name:        d.Name,
				Description: d.Description,
				Parameters:  d.Parameters,
			},
		}
	}
	return tools
}

// Chat sends a non-streaming chat request to Ollama.
func (p *OllamaProvider) Chat(ctx context.Context, messages []Message, opts ChatOptions) (Response, error) {
	model := opts.Model
	if model == "" {
		model = p.Model
	}

	msgs := make([]ollamaMsg, len(messages))
	for i, m := range messages {
		msgs[i] = ollamaMsg{Role: m.Role, Content: m.Content}
	}

	reqBody := ollamaRequest{
		Model:    model,
		Messages: msgs,
		Stream:   false,
		Tools:    p.buildTools(opts.Tools),
	}
	body, err := json.Marshal(reqBody)
	if err != nil {
		return Response{}, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", p.BaseURL+"/api/chat", bytes.NewReader(body))
	if err != nil {
		return Response{}, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.HTTPClient.Do(req)
	if err != nil {
		return Response{}, fmt.Errorf("ollama chat: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return Response{}, fmt.Errorf("ollama HTTP %d", resp.StatusCode)
	}

	var result ollamaResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return Response{}, fmt.Errorf("decode response: %w", err)
	}

	var toolCalls []ToolCall
	for _, tc := range result.Message.ToolCalls {
		args, _ := json.Marshal(tc.Function.Arguments)
		toolCalls = append(toolCalls, ToolCall{
			ID: fmt.Sprintf("call_%s", tc.Function.Name),
			Function: FunctionCall{
				Name:      tc.Function.Name,
				Arguments: string(args),
			},
		})
	}

	return Response{
		Content:   result.Message.Content,
		ToolCalls: toolCalls,
		Usage: Usage{
			PromptTokens:     result.PromptEvalCount,
			CompletionTokens: result.EvalCount,
			TotalTokens:      result.PromptEvalCount + result.EvalCount,
		},
		Model:        result.Model,
		FinishReason: result.DoneReason,
	}, nil
}

// ChatStream sends a streaming chat request to Ollama.
func (p *OllamaProvider) ChatStream(ctx context.Context, messages []Message, opts ChatOptions) (<-chan string, <-chan error) {
	chunks := make(chan string, 64)
	errc := make(chan error, 1)

	go func() {
		defer close(chunks)
		defer close(errc)

		model := opts.Model
		if model == "" {
			model = p.Model
		}

		msgs := make([]ollamaMsg, len(messages))
		for i, m := range messages {
			msgs[i] = ollamaMsg{Role: m.Role, Content: m.Content}
		}

		reqBody := ollamaRequest{
			Model:    model,
			Messages: msgs,
			Stream:   true,
			Tools:    p.buildTools(opts.Tools),
		}
		body, err := json.Marshal(reqBody)
		if err != nil {
			errc <- fmt.Errorf("marshal request: %w", err)
			return
		}

		req, err := http.NewRequestWithContext(ctx, "POST", p.BaseURL+"/api/chat", bytes.NewReader(body))
		if err != nil {
			errc <- fmt.Errorf("create request: %w", err)
			return
		}
		req.Header.Set("Content-Type", "application/json")

		resp, err := p.HTTPClient.Do(req)
		if err != nil {
			errc <- fmt.Errorf("ollama stream: %w", err)
			return
		}
		defer resp.Body.Close()

		scanner := bufio.NewScanner(resp.Body)
		for scanner.Scan() {
			line := scanner.Text()
			if strings.TrimSpace(line) == "" {
				continue
			}
			var chunk ollamaResponse
			if err := json.Unmarshal([]byte(line), &chunk); err != nil {
				continue
			}
			if chunk.Message.Content != "" {
				chunks <- chunk.Message.Content
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
| `OLLAMA_HOST` | No | Ollama server URL (default: `http://localhost:11434`) |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | Go module path |

## Dependencies

No external dependencies. Uses Go standard library only.
