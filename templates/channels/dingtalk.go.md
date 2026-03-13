# DingTalk Channel Adapter (Go)

DingTalk bot channel adapter using the Stream protocol. DingTalk Stream connects via WebSocket to receive messages without a public endpoint. Uses `gorilla/websocket` as the single external dependency.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DINGTALK_CLIENT_ID` | App Key from DingTalk Developer Console |
| `DINGTALK_CLIENT_SECRET` | App Secret from DingTalk Developer Console |

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
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

// DingTalkChannel implements the Channel interface for DingTalk Stream.
type DingTalkChannel struct {
	clientID     string
	clientSecret string
	handler      MessageHandler
	conn         *websocket.Conn
	accessToken  string
	cancelFunc   context.CancelFunc
}

// NewDingTalkChannel creates a new DingTalk adapter from environment variables.
func NewDingTalkChannel(handler MessageHandler) (*DingTalkChannel, error) {
	clientID := os.Getenv("DINGTALK_CLIENT_ID")
	clientSecret := os.Getenv("DINGTALK_CLIENT_SECRET")
	if clientID == "" || clientSecret == "" {
		return nil, fmt.Errorf("DINGTALK_CLIENT_ID and DINGTALK_CLIENT_SECRET are required")
	}
	return &DingTalkChannel{
		clientID:     clientID,
		clientSecret: clientSecret,
		handler:      handler,
	}, nil
}

// Start registers for Stream mode and listens for messages.
func (d *DingTalkChannel) Start(ctx context.Context) error {
	ctx, d.cancelFunc = context.WithCancel(ctx)

	ticket, endpoint, err := d.registerStream()
	if err != nil {
		return fmt.Errorf("stream registration failed: %w", err)
	}

	wsURL := fmt.Sprintf("%s?ticket=%s", endpoint, url.QueryEscape(ticket))
	conn, _, err := websocket.DefaultDialer.DialContext(ctx, wsURL, nil)
	if err != nil {
		return fmt.Errorf("websocket dial failed: %w", err)
	}
	d.conn = conn
	defer conn.Close()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		_, raw, err := conn.ReadMessage()
		if err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			log.Printf("[dingtalk] read error: %v", err)
			return err
		}

		var envelope dtEnvelope
		if err := json.Unmarshal(raw, &envelope); err != nil {
			log.Printf("[dingtalk] unmarshal error: %v", err)
			continue
		}

		// Respond to system pings.
		if envelope.Type == "SYSTEM" {
			ack := map[string]interface{}{"code": 200, "headers": envelope.Headers, "message": "OK", "data": ""}
			conn.WriteJSON(ack)
			continue
		}

		if envelope.Type == "CALLBACK" {
			var data dtMessageData
			if err := json.Unmarshal([]byte(envelope.Data), &data); err == nil && data.Text.Content != "" {
				d.handler(IncomingMessage{
					ChannelID: "dingtalk",
					ChatID:    data.ConversationID,
					SenderID:  data.SenderID,
					Text:      strings.TrimSpace(data.Text.Content),
					Timestamp: time.Now(),
				})
			}
			ack := map[string]interface{}{"code": 200, "headers": envelope.Headers, "message": "OK", "data": ""}
			conn.WriteJSON(ack)
		}
	}
}

// Stop closes the stream connection.
func (d *DingTalkChannel) Stop() error {
	if d.cancelFunc != nil {
		d.cancelFunc()
	}
	if d.conn != nil {
		return d.conn.Close()
	}
	return nil
}

// SendMessage sends a message to a DingTalk conversation via webhook or API.
func (d *DingTalkChannel) SendMessage(chatID string, text string) error {
	if d.accessToken == "" {
		if err := d.refreshToken(); err != nil {
			return err
		}
	}
	payload, _ := json.Marshal(map[string]interface{}{
		"msgKey":            "sampleText",
		"msgParam":          fmt.Sprintf(`{"content":"%s"}`, text),
		"openConversationId": chatID,
	})
	url := "https://api.dingtalk.com/v1.0/robot/groupMessages/send"
	req, _ := http.NewRequest(http.MethodPost, url, strings.NewReader(string(payload)))
	req.Header.Set("x-acs-dingtalk-access-token", d.accessToken)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("dingtalk API returned %d: %s", resp.StatusCode, body)
	}
	return nil
}

func (d *DingTalkChannel) refreshToken() error {
	payload, _ := json.Marshal(map[string]string{
		"appKey":    d.clientID,
		"appSecret": d.clientSecret,
	})
	resp, err := http.Post("https://api.dingtalk.com/v1.0/oauth2/accessToken",
		"application/json", strings.NewReader(string(payload)))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	var result struct {
		AccessToken string `json:"accessToken"`
	}
	json.NewDecoder(resp.Body).Decode(&result)
	d.accessToken = result.AccessToken
	return nil
}

func (d *DingTalkChannel) registerStream() (string, string, error) {
	if err := d.refreshToken(); err != nil {
		return "", "", err
	}
	payload, _ := json.Marshal(map[string]interface{}{
		"clientId":     d.clientID,
		"clientSecret": d.clientSecret,
		"subscriptions": []map[string]string{
			{"type": "EVENT", "topic": "/v1.0/im/bot/messages/get"},
		},
	})
	req, _ := http.NewRequest(http.MethodPost,
		"https://api.dingtalk.com/v1.0/gateway/connections/open",
		strings.NewReader(string(payload)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	var result struct {
		Ticket   string `json:"ticket"`
		Endpoint string `json:"endpoint"`
	}
	json.NewDecoder(resp.Body).Decode(&result)
	return result.Ticket, result.Endpoint, nil
}

type dtEnvelope struct {
	Type    string            `json:"type"`
	Headers map[string]string `json:"headers"`
	Data    string            `json:"data"`
}

type dtMessageData struct {
	ConversationID string `json:"conversationId"`
	SenderID       string `json:"senderId"`
	Text           struct {
		Content string `json:"content"`
	} `json:"text"`
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

	ch, err := channels.NewDingTalkChannel(func(msg channels.IncomingMessage) {
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
