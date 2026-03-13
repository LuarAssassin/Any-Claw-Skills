# Provider: OpenAI (Go)

Template for OpenAI LLM provider integration using net/http (no SDK).

## Generated File: `providers/openai.go`

```go
// Package providers implements LLM provider integrations for {{PROJECT_NAME}}.
package providers

import (
	"bytes"
	"bufio"
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

// Message represents a chat message.
type Message struct {
	Role       string     `json:"role"`
	Content    string     `json:"content"`
	ToolCalls  []ToolCall `json:"tool_calls,omitempty"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
}

// ToolDef defines a tool the model can call.
type ToolDef struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Parameters  map[string]any `json:"parameters"`
}

// ToolCall represents a tool invocation from the model.
type ToolCall struct {
	ID       string       `json:"id"`
	Function FunctionCall `json:"function"`
}

// FunctionCall holds the function name and arguments.
type FunctionCall struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

// Usage holds token usage information.
type Usage struct {
	PromptTokens     int `json:"prompt_tokens"`
	CompletionTokens int `json:"completion_tokens"`
	TotalTokens      int `json:"total_tokens"`
}

// Response holds the result of a chat completion.
type Response struct {
	Content      string     `json:"content"`
	ToolCalls    []ToolCall `json:"tool_calls"`
	Usage        Usage      `json:"usage"`
	Model        string     `json:"model"`
	FinishReason string     `json:"finish_reason"`
}

// ChatOptions holds optional parameters for a chat call.
type ChatOptions struct {
	Tools     []ToolDef
	Stream    bool
	Model     string
	MaxTokens int
}

// Provider is the interface all LLM providers implement.
type Provider interface {
	Chat(ctx context.Context, messages []Message, opts ChatOptions) (Response, error)
	ChatStream(ctx context.Context, messages []Message, opts ChatOptions) (<-chan string, <-chan error)
}

// OpenAIProvider implements the Provider interface for OpenAI.
type OpenAIProvider struct {
	APIKey     string
	Model      string
	BaseURL    string
	MaxRetries int
	HTTPClient *http.Client
}

// NewOpenAIProvider creates a new OpenAI provider.
func NewOpenAIProvider(model string) *OpenAIProvider {
	apiKey := os.Getenv("OPENAI_API_KEY")
	baseURL := os.Getenv("OPENAI_BASE_URL")
	if baseURL == "" {
		baseURL = "https://api.openai.com/v1"
	}
	if model == "" {
		model = "gpt-4o"
	}
	return &OpenAIProvider{
		APIKey:     apiKey,
		Model:      model,
		BaseURL:    strings.TrimRight(baseURL, "/"),
		MaxRetries: 3,
		HTTPClient: &http.Client{Timeout: 60 * time.Second},
	}
}

type openaiRequest struct {
	Model    string        `json:"model"`
	Messages []Message     `json:"messages"`
	Tools    []openaiTool  `json:"tools,omitempty"`
	Stream   bool          `json:"stream,omitempty"`
}

type openaiTool struct {
	Type     string         `json:"type"`
	Function openaiFunction `json:"function"`
}

type openaiFunction struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Parameters  map[string]any `json:"parameters"`
}

type openaiResponse struct {
	Choices []openaiChoice `json:"choices"`
	Usage   Usage          `json:"usage"`
	Model   string         `json:"model"`
}

type openaiChoice struct {
	Message      openaiMessage `json:"message"`
	Delta        openaiMessage `json:"delta"`
	FinishReason string        `json:"finish_reason"`
}

type openaiMessage struct {
	Content   string     `json:"content"`
	ToolCalls []ToolCall `json:"tool_calls,omitempty"`
}

func (p *OpenAIProvider) buildTools(defs []ToolDef) []openaiTool {
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

func (p *OpenAIProvider) doRequest(ctx context.Context, body []byte, stream bool) (*http.Response, error) {
	var lastErr error
	for attempt := 0; attempt < p.MaxRetries; attempt++ {
		req, err := http.NewRequestWithContext(ctx, "POST", p.BaseURL+"/chat/completions", bytes.NewReader(body))
		if err != nil {
			return nil, fmt.Errorf("create request: %w", err)
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+p.APIKey)

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
			return nil, fmt.Errorf("OpenAI API error %d: %s", resp.StatusCode, string(respBody))
		}
		return resp, nil
	}
	return nil, fmt.Errorf("max retries exceeded: %w", lastErr)
}

// Chat sends a non-streaming chat completion request.
func (p *OpenAIProvider) Chat(ctx context.Context, messages []Message, opts ChatOptions) (Response, error) {
	model := opts.Model
	if model == "" {
		model = p.Model
	}
	reqBody := openaiRequest{
		Model:    model,
		Messages: messages,
		Tools:    p.buildTools(opts.Tools),
		Stream:   false,
	}
	body, err := json.Marshal(reqBody)
	if err != nil {
		return Response{}, fmt.Errorf("marshal request: %w", err)
	}

	resp, err := p.doRequest(ctx, body, false)
	if err != nil {
		return Response{}, err
	}
	defer resp.Body.Close()

	var result openaiResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return Response{}, fmt.Errorf("decode response: %w", err)
	}
	if len(result.Choices) == 0 {
		return Response{}, fmt.Errorf("no choices in response")
	}

	choice := result.Choices[0]
	return Response{
		Content:      choice.Message.Content,
		ToolCalls:    choice.Message.ToolCalls,
		Usage:        result.Usage,
		Model:        result.Model,
		FinishReason: choice.FinishReason,
	}, nil
}

// ChatStream sends a streaming chat completion request.
func (p *OpenAIProvider) ChatStream(ctx context.Context, messages []Message, opts ChatOptions) (<-chan string, <-chan error) {
	chunks := make(chan string, 64)
	errc := make(chan error, 1)

	go func() {
		defer close(chunks)
		defer close(errc)

		model := opts.Model
		if model == "" {
			model = p.Model
		}
		reqBody := openaiRequest{
			Model:    model,
			Messages: messages,
			Tools:    p.buildTools(opts.Tools),
			Stream:   true,
		}
		body, err := json.Marshal(reqBody)
		if err != nil {
			errc <- fmt.Errorf("marshal request: %w", err)
			return
		}

		resp, err := p.doRequest(ctx, body, true)
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
			if data == "[DONE]" {
				break
			}
			var chunk openaiResponse
			if err := json.Unmarshal([]byte(data), &chunk); err != nil {
				continue
			}
			if len(chunk.Choices) > 0 && chunk.Choices[0].Delta.Content != "" {
				chunks <- chunk.Choices[0].Delta.Content
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
| `OPENAI_API_KEY` | Yes | OpenAI API key |
| `OPENAI_BASE_URL` | No | Override base URL for OpenAI-compatible APIs |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | Go module path |

## Dependencies

No external dependencies. Uses Go standard library only.
