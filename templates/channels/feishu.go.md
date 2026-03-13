# Feishu/Lark Channel Adapter (Go)

Feishu (Lark) channel adapter using the Event Subscription HTTP callback model. Receives messages via webhook POST and sends replies through the Feishu Open API. Uses only the Go standard library.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `FEISHU_APP_ID` | App ID from Feishu Developer Console |
| `FEISHU_APP_SECRET` | App Secret from Feishu Developer Console |
| `FEISHU_VERIFICATION_TOKEN` | Event verification token |
| `FEISHU_LISTEN_ADDR` | HTTP listen address (default: `:8080`) |

## Code

```go
package channels

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// FeishuChannel implements the Channel interface for Feishu/Lark.
type FeishuChannel struct {
	appID       string
	appSecret   string
	verifyToken string
	listenAddr  string
	handler     MessageHandler
	server      *http.Server
	accessToken string
	tokenExpiry time.Time
	mu          sync.Mutex
}

// NewFeishuChannel creates a new Feishu adapter from environment variables.
func NewFeishuChannel(handler MessageHandler) (*FeishuChannel, error) {
	appID := os.Getenv("FEISHU_APP_ID")
	appSecret := os.Getenv("FEISHU_APP_SECRET")
	verifyToken := os.Getenv("FEISHU_VERIFICATION_TOKEN")
	if appID == "" || appSecret == "" || verifyToken == "" {
		return nil, fmt.Errorf("FEISHU_APP_ID, FEISHU_APP_SECRET, and FEISHU_VERIFICATION_TOKEN are required")
	}
	addr := os.Getenv("FEISHU_LISTEN_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	return &FeishuChannel{
		appID:       appID,
		appSecret:   appSecret,
		verifyToken: verifyToken,
		listenAddr:  addr,
		handler:     handler,
	}, nil
}

// Start begins the HTTP server for receiving event callbacks.
func (f *FeishuChannel) Start(ctx context.Context) error {
	mux := http.NewServeMux()
	mux.HandleFunc("/webhook", f.eventHandler)

	f.server = &http.Server{Addr: f.listenAddr, Handler: mux}

	go func() {
		<-ctx.Done()
		f.server.Close()
	}()

	log.Printf("[feishu] listening on %s/webhook", f.listenAddr)
	if err := f.server.ListenAndServe(); err != http.ErrServerClosed {
		return err
	}
	return nil
}

// Stop shuts down the HTTP server.
func (f *FeishuChannel) Stop() error {
	if f.server != nil {
		return f.server.Close()
	}
	return nil
}

// SendMessage sends a text message to a Feishu chat.
func (f *FeishuChannel) SendMessage(chatID string, text string) error {
	token, err := f.getAccessToken()
	if err != nil {
		return fmt.Errorf("failed to get access token: %w", err)
	}
	payload, _ := json.Marshal(map[string]interface{}{
		"receive_id": chatID,
		"msg_type":   "text",
		"content":    fmt.Sprintf(`{"text":"%s"}`, text),
	})
	url := "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id"
	req, err := http.NewRequest(http.MethodPost, url, strings.NewReader(string(payload)))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("feishu API returned %d: %s", resp.StatusCode, body)
	}
	return nil
}

func (f *FeishuChannel) eventHandler(rw http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(rw, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	defer r.Body.Close()
	body, _ := io.ReadAll(r.Body)

	// URL verification challenge.
	var challenge struct {
		Challenge string `json:"challenge"`
		Token     string `json:"token"`
		Type      string `json:"type"`
	}
	if err := json.Unmarshal(body, &challenge); err == nil && challenge.Type == "url_verification" {
		if challenge.Token != f.verifyToken {
			http.Error(rw, "forbidden", http.StatusForbidden)
			return
		}
		rw.Header().Set("Content-Type", "application/json")
		json.NewEncoder(rw).Encode(map[string]string{"challenge": challenge.Challenge})
		return
	}

	// Event callback.
	var event fsEvent
	if err := json.Unmarshal(body, &event); err != nil {
		http.Error(rw, "bad request", http.StatusBadRequest)
		return
	}
	rw.WriteHeader(http.StatusOK)

	if event.Header.Token != f.verifyToken {
		return
	}
	if event.Header.EventType == "im.message.receive_v1" {
		msg := event.Event
		if msg.Message.MessageType == "text" {
			var content struct {
				Text string `json:"text"`
			}
			json.Unmarshal([]byte(msg.Message.Content), &content)
			f.handler(IncomingMessage{
				ChannelID: "feishu",
				ChatID:    msg.Message.ChatID,
				SenderID:  msg.Sender.SenderID.OpenID,
				Text:      content.Text,
				Timestamp: time.Now(),
			})
		}
	}
}

func (f *FeishuChannel) getAccessToken() (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.accessToken != "" && time.Now().Before(f.tokenExpiry) {
		return f.accessToken, nil
	}
	payload, _ := json.Marshal(map[string]string{
		"app_id":     f.appID,
		"app_secret": f.appSecret,
	})
	resp, err := http.Post("https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
		"application/json; charset=utf-8", strings.NewReader(string(payload)))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var result struct {
		Code              int    `json:"code"`
		Expire            int    `json:"expire"`
		TenantAccessToken string `json:"tenant_access_token"`
	}
	json.NewDecoder(resp.Body).Decode(&result)
	f.accessToken = result.TenantAccessToken
	f.tokenExpiry = time.Now().Add(time.Duration(result.Expire-60) * time.Second)
	return f.accessToken, nil
}

type fsEvent struct {
	Header struct {
		Token     string `json:"token"`
		EventType string `json:"event_type"`
	} `json:"header"`
	Event struct {
		Sender struct {
			SenderID struct {
				OpenID string `json:"open_id"`
			} `json:"sender_id"`
		} `json:"sender"`
		Message struct {
			ChatID      string `json:"chat_id"`
			MessageType string `json:"message_type"`
			Content     string `json:"content"`
		} `json:"message"`
	} `json:"event"`
}
```

## Usage

```go
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"

	"{{PROJECT_NAME}}/channels"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	ch, err := channels.NewFeishuChannel(func(msg channels.IncomingMessage) {
		fmt.Printf("[%s] %s: %s\n", msg.ChatID, msg.SenderID, msg.Text)
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
	if err := ch.Start(ctx); err != nil && err != context.Canceled {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
```
