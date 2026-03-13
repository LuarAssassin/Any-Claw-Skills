# main.go.md

Template for the Pico/Go tier scaffold. A complete single-file personal assistant
written in pure Go standard library.

## Generated File: `main.go`

```go
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	{{CHANNEL_IMPORT}}
)

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

type Config struct {
	// Core
	ProjectName string
	Port        string
	LogLevel    string

	// LLM Provider
	ProviderAPIKey  string
	ProviderBaseURL string
	ProviderModel   string

	// Channel
	ChannelToken  string
	ChannelSecret string

	// Personality
	SystemPrompt string
}

func LoadConfig() Config {
	cfg := Config{
		ProjectName:     envOr("PROJECT_NAME", "{{PROJECT_NAME}}"),
		Port:            envOr("PORT", "8080"),
		LogLevel:        envOr("LOG_LEVEL", "info"),
		ProviderAPIKey:  mustEnv("PROVIDER_API_KEY"),
		ProviderBaseURL: envOr("PROVIDER_BASE_URL", "{{PROVIDER_DEFAULT_URL}}"),
		ProviderModel:   envOr("PROVIDER_MODEL", "{{PROVIDER_DEFAULT_MODEL}}"),
		ChannelToken:    envOr("CHANNEL_TOKEN", ""),
		ChannelSecret:   envOr("CHANNEL_SECRET", ""),
		SystemPrompt:    envOr("SYSTEM_PROMPT", "You are {{ASSISTANT_NAME}}, a helpful personal assistant."),
	}
	return cfg
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("required environment variable %s is not set", key)
	}
	return v
}

// ---------------------------------------------------------------------------
// Conversation Memory (in-process, bounded)
// ---------------------------------------------------------------------------

type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type Conversation struct {
	mu       sync.Mutex
	messages []Message
	maxTurns int
}

func NewConversation(systemPrompt string, maxTurns int) *Conversation {
	return &Conversation{
		messages: []Message{
			{Role: "system", Content: systemPrompt},
		},
		maxTurns: maxTurns,
	}
}

func (c *Conversation) Add(role, content string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.messages = append(c.messages, Message{Role: role, Content: content})
	// Keep the system message plus the last maxTurns*2 user/assistant pairs.
	limit := 1 + c.maxTurns*2
	if len(c.messages) > limit {
		trimmed := make([]Message, 0, limit)
		trimmed = append(trimmed, c.messages[0]) // system
		trimmed = append(trimmed, c.messages[len(c.messages)-c.maxTurns*2:]...)
		c.messages = trimmed
	}
}

func (c *Conversation) Snapshot() []Message {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]Message, len(c.messages))
	copy(out, c.messages)
	return out
}

func (c *Conversation) Reset(systemPrompt string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.messages = []Message{
		{Role: "system", Content: systemPrompt},
	}
}

// ---------------------------------------------------------------------------
// Conversation Store (per-user)
// ---------------------------------------------------------------------------

type ConversationStore struct {
	mu           sync.Mutex
	convos       map[string]*Conversation
	systemPrompt string
	maxTurns     int
}

func NewConversationStore(systemPrompt string, maxTurns int) *ConversationStore {
	return &ConversationStore{
		convos:       make(map[string]*Conversation),
		systemPrompt: systemPrompt,
		maxTurns:     maxTurns,
	}
}

func (s *ConversationStore) Get(userID string) *Conversation {
	s.mu.Lock()
	defer s.mu.Unlock()
	if c, ok := s.convos[userID]; ok {
		return c
	}
	c := NewConversation(s.systemPrompt, s.maxTurns)
	s.convos[userID] = c
	return c
}

// ---------------------------------------------------------------------------
// LLM Provider Client
// ---------------------------------------------------------------------------

{{PROVIDER_SETUP}}

type LLMClient struct {
	httpClient *http.Client
	baseURL    string
	apiKey     string
	model      string
}

func NewLLMClient(cfg Config) *LLMClient {
	return &LLMClient{
		httpClient: &http.Client{Timeout: 60 * time.Second},
		baseURL:    strings.TrimRight(cfg.ProviderBaseURL, "/"),
		apiKey:     cfg.ProviderAPIKey,
		model:      cfg.ProviderModel,
	}
}

type chatRequest struct {
	Model    string    `json:"model"`
	Messages []Message `json:"messages"`
}

type chatResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

func (c *LLMClient) Complete(ctx context.Context, messages []Message) (string, error) {
	reqBody := chatRequest{
		Model:    c.model,
		Messages: messages,
	}
	payload, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	endpoint := c.baseURL + "/chat/completions"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("provider returned %d: %s", resp.StatusCode, string(body))
	}

	var chatResp chatResponse
	if err := json.Unmarshal(body, &chatResp); err != nil {
		return "", fmt.Errorf("unmarshal response: %w", err)
	}
	if chatResp.Error != nil {
		return "", fmt.Errorf("provider error: %s", chatResp.Error.Message)
	}
	if len(chatResp.Choices) == 0 {
		return "", fmt.Errorf("provider returned no choices")
	}
	return strings.TrimSpace(chatResp.Choices[0].Message.Content), nil
}

// ---------------------------------------------------------------------------
// Channel Handler
// ---------------------------------------------------------------------------

{{CHANNEL_SETUP}}

// ---------------------------------------------------------------------------
// HTTP Server & Routes
// ---------------------------------------------------------------------------

type App struct {
	cfg    Config
	llm    *LLMClient
	store  *ConversationStore
	mux    *http.ServeMux
	server *http.Server
}

func NewApp(cfg Config) *App {
	app := &App{
		cfg:   cfg,
		llm:   NewLLMClient(cfg),
		store: NewConversationStore(cfg.SystemPrompt, 20),
		mux:   http.NewServeMux(),
	}
	app.routes()
	app.server = &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      app.mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 90 * time.Second,
		IdleTimeout:  120 * time.Second,
	}
	return app
}

func (a *App) routes() {
	a.mux.HandleFunc("GET /health", a.handleHealth)
	a.mux.HandleFunc("POST /chat", a.handleChat)
	a.mux.HandleFunc("POST /webhook", a.handleWebhook)
	a.mux.HandleFunc("POST /reset", a.handleReset)
}

// GET /health -- liveness check
func (a *App) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "ok",
		"project": a.cfg.ProjectName,
	})
}

// POST /chat -- direct JSON chat
type chatInput struct {
	UserID  string `json:"user_id"`
	Message string `json:"message"`
}

type chatOutput struct {
	Reply string `json:"reply"`
	Error string `json:"error,omitempty"`
}

func (a *App) handleChat(w http.ResponseWriter, r *http.Request) {
	var in chatInput
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeJSON(w, http.StatusBadRequest, chatOutput{Error: "invalid request body"})
		return
	}
	if in.Message == "" {
		writeJSON(w, http.StatusBadRequest, chatOutput{Error: "message is required"})
		return
	}
	if in.UserID == "" {
		in.UserID = "default"
	}

	convo := a.store.Get(in.UserID)
	convo.Add("user", in.Message)

	reply, err := a.llm.Complete(r.Context(), convo.Snapshot())
	if err != nil {
		log.Printf("[error] llm complete: %v", err)
		writeJSON(w, http.StatusBadGateway, chatOutput{Error: "failed to get response from provider"})
		return
	}

	convo.Add("assistant", reply)
	writeJSON(w, http.StatusOK, chatOutput{Reply: reply})
}

// POST /webhook -- channel-specific incoming messages
func (a *App) handleWebhook(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "cannot read body"})
		return
	}

	userID, userMsg, err := parseChannelMessage(body, a.cfg)
	if err != nil {
		log.Printf("[warn] webhook parse: %v", err)
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}

	convo := a.store.Get(userID)
	convo.Add("user", userMsg)

	reply, err := a.llm.Complete(r.Context(), convo.Snapshot())
	if err != nil {
		log.Printf("[error] llm complete: %v", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "provider failure"})
		return
	}

	convo.Add("assistant", reply)

	if sendErr := sendChannelReply(userID, reply, a.cfg); sendErr != nil {
		log.Printf("[error] channel reply: %v", sendErr)
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// POST /reset -- clear a user's conversation
func (a *App) handleReset(w http.ResponseWriter, r *http.Request) {
	var in struct {
		UserID string `json:"user_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.UserID == "" {
		in.UserID = "default"
	}
	convo := a.store.Get(in.UserID)
	convo.Reset(a.cfg.SystemPrompt)
	writeJSON(w, http.StatusOK, map[string]string{"status": "reset"})
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

// parseChannelMessage extracts user ID and text from the channel-specific
// webhook payload. Replace this stub with real parsing logic for your channel.
func parseChannelMessage(body []byte, cfg Config) (userID, text string, err error) {
	var payload struct {
		UserID  string `json:"user_id"`
		Message string `json:"message"`
		Text    string `json:"text"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return "", "", fmt.Errorf("unmarshal webhook: %w", err)
	}
	uid := payload.UserID
	if uid == "" {
		uid = "webhook-user"
	}
	msg := payload.Message
	if msg == "" {
		msg = payload.Text
	}
	if msg == "" {
		return "", "", fmt.Errorf("no message content in webhook payload")
	}
	return uid, msg, nil
}

// sendChannelReply posts the assistant's reply back to the channel.
// Replace this stub with real channel API calls.
func sendChannelReply(userID, reply string, cfg Config) error {
	log.Printf("[channel] -> %s: %s", userID, reply)
	// {{CHANNEL_REPLY_IMPL}}
	return nil
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

func main() {
	cfg := LoadConfig()

	log.Printf("starting %s on :%s", cfg.ProjectName, cfg.Port)
	log.Printf("provider: %s model: %s", cfg.ProviderBaseURL, cfg.ProviderModel)

	app := NewApp(cfg)

	// Graceful shutdown
	done := make(chan os.Signal, 1)
	signal.Notify(done, os.Interrupt, syscall.SIGTERM)

	go func() {
		if err := app.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	log.Printf("server ready -- endpoints: GET /health, POST /chat, POST /webhook, POST /reset")

	<-done
	log.Println("shutting down...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := app.server.Shutdown(ctx); err != nil {
		log.Fatalf("shutdown error: %v", err)
	}
	log.Println("goodbye")
}
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Go module and project name (e.g. `myassistant`) |
| `{{ASSISTANT_NAME}}` | Display name of the assistant persona |
| `{{CHANNEL_IMPORT}}` | Additional import paths required by the chosen channel adapter |
| `{{CHANNEL_SETUP}}` | Channel-specific initialization code (webhook verification, polling loop, etc.) |
| `{{CHANNEL_REPLY_IMPL}}` | Implementation body for sending replies back through the channel API |
| `{{PROVIDER_SETUP}}` | Any provider-specific constants, helpers, or auth setup beyond the base OpenAI-compatible client |
| `{{PROVIDER_DEFAULT_URL}}` | Default base URL for the LLM provider (e.g. `https://api.openai.com/v1`) |
| `{{PROVIDER_DEFAULT_MODEL}}` | Default model identifier (e.g. `gpt-4o-mini`, `claude-3-haiku-20240307`) |
