# WhatsApp Channel Adapter (Go)

WhatsApp Cloud API channel adapter. Receives messages via an incoming webhook HTTP handler and sends replies through the Cloud API. Uses only the Go standard library.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `WHATSAPP_TOKEN` | Permanent access token from Meta for Business |
| `WHATSAPP_PHONE_ID` | Phone number ID from WhatsApp Business settings |
| `WHATSAPP_VERIFY_TOKEN` | Webhook verification token (you choose this value) |
| `WHATSAPP_LISTEN_ADDR` | HTTP listen address (default: `:8080`) |

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
	"time"
)

// WhatsAppChannel implements the Channel interface for WhatsApp Cloud API.
type WhatsAppChannel struct {
	token       string
	phoneID     string
	verifyToken string
	listenAddr  string
	handler     MessageHandler
	server      *http.Server
}

// NewWhatsAppChannel creates a new WhatsApp adapter from environment variables.
func NewWhatsAppChannel(handler MessageHandler) (*WhatsAppChannel, error) {
	token := os.Getenv("WHATSAPP_TOKEN")
	phoneID := os.Getenv("WHATSAPP_PHONE_ID")
	verifyToken := os.Getenv("WHATSAPP_VERIFY_TOKEN")
	if token == "" || phoneID == "" || verifyToken == "" {
		return nil, fmt.Errorf("WHATSAPP_TOKEN, WHATSAPP_PHONE_ID, and WHATSAPP_VERIFY_TOKEN are required")
	}
	addr := os.Getenv("WHATSAPP_LISTEN_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	return &WhatsAppChannel{
		token:       token,
		phoneID:     phoneID,
		verifyToken: verifyToken,
		listenAddr:  addr,
		handler:     handler,
	}, nil
}

// Start begins listening for incoming webhook events.
func (w *WhatsAppChannel) Start(ctx context.Context) error {
	mux := http.NewServeMux()
	mux.HandleFunc("/webhook", w.webhookHandler)

	w.server = &http.Server{Addr: w.listenAddr, Handler: mux}

	go func() {
		<-ctx.Done()
		w.server.Close()
	}()

	log.Printf("[whatsapp] listening on %s/webhook", w.listenAddr)
	if err := w.server.ListenAndServe(); err != http.ErrServerClosed {
		return err
	}
	return nil
}

// Stop shuts down the HTTP server.
func (w *WhatsAppChannel) Stop() error {
	if w.server != nil {
		return w.server.Close()
	}
	return nil
}

// SendMessage sends a text message to a WhatsApp phone number.
func (w *WhatsAppChannel) SendMessage(chatID string, text string) error {
	payload, _ := json.Marshal(map[string]interface{}{
		"messaging_product": "whatsapp",
		"to":                chatID,
		"type":              "text",
		"text":              map[string]string{"body": text},
	})
	url := fmt.Sprintf("https://graph.facebook.com/v21.0/%s/messages", w.phoneID)
	req, err := http.NewRequest(http.MethodPost, url, strings.NewReader(string(payload)))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+w.token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("whatsapp API request failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("whatsapp API returned %d: %s", resp.StatusCode, body)
	}
	return nil
}

func (w *WhatsAppChannel) webhookHandler(rw http.ResponseWriter, r *http.Request) {
	// Verification challenge (GET).
	if r.Method == http.MethodGet {
		mode := r.URL.Query().Get("hub.mode")
		token := r.URL.Query().Get("hub.verify_token")
		challenge := r.URL.Query().Get("hub.challenge")
		if mode == "subscribe" && token == w.verifyToken {
			rw.WriteHeader(http.StatusOK)
			fmt.Fprint(rw, challenge)
			return
		}
		http.Error(rw, "forbidden", http.StatusForbidden)
		return
	}

	// Incoming message (POST).
	if r.Method != http.MethodPost {
		http.Error(rw, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	defer r.Body.Close()
	var body waWebhookBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(rw, "bad request", http.StatusBadRequest)
		return
	}
	rw.WriteHeader(http.StatusOK)

	for _, entry := range body.Entry {
		for _, change := range entry.Changes {
			for _, msg := range change.Value.Messages {
				if msg.Type == "text" {
					w.handler(IncomingMessage{
						ChannelID: "whatsapp",
						ChatID:    msg.From,
						SenderID:  msg.From,
						Text:      msg.Text.Body,
						Timestamp: time.Now(),
					})
				}
			}
		}
	}
}

type waWebhookBody struct {
	Entry []struct {
		Changes []struct {
			Value struct {
				Messages []struct {
					From string `json:"from"`
					Type string `json:"type"`
					Text struct {
						Body string `json:"body"`
					} `json:"text"`
				} `json:"messages"`
			} `json:"value"`
		} `json:"changes"`
	} `json:"entry"`
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

	ch, err := channels.NewWhatsAppChannel(func(msg channels.IncomingMessage) {
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
