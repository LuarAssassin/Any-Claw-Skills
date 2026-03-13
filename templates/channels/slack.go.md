# Slack Channel Adapter (Go)

Slack channel adapter using Socket Mode. Socket Mode connects via WebSocket to receive events without exposing a public HTTP endpoint. Uses `gorilla/websocket` as the single external dependency (Go stdlib lacks a WebSocket client). Messages are sent back via the Slack Web API over HTTP.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SLACK_BOT_TOKEN` | Bot User OAuth Token (`xoxb-...`) |
| `SLACK_APP_TOKEN` | App-Level Token (`xapp-...`) for Socket Mode |

## Code

```go
package channels

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

// SlackChannel implements the Channel interface for Slack Socket Mode.
type SlackChannel struct {
	botToken   string
	appToken   string
	handler    MessageHandler
	conn       *websocket.Conn
	cancelFunc context.CancelFunc
}

// NewSlackChannel creates a new Slack adapter from environment variables.
func NewSlackChannel(handler MessageHandler) (*SlackChannel, error) {
	botToken := os.Getenv("SLACK_BOT_TOKEN")
	appToken := os.Getenv("SLACK_APP_TOKEN")
	if botToken == "" || appToken == "" {
		return nil, fmt.Errorf("SLACK_BOT_TOKEN and SLACK_APP_TOKEN are required")
	}
	return &SlackChannel{
		botToken: botToken,
		appToken: appToken,
		handler:  handler,
	}, nil
}

// Start opens a Socket Mode WebSocket and listens for events.
func (s *SlackChannel) Start(ctx context.Context) error {
	ctx, s.cancelFunc = context.WithCancel(ctx)

	wsURL, err := s.openConnection()
	if err != nil {
		return fmt.Errorf("failed to open socket mode connection: %w", err)
	}

	conn, _, err := websocket.DefaultDialer.DialContext(ctx, wsURL, nil)
	if err != nil {
		return fmt.Errorf("websocket dial failed: %w", err)
	}
	s.conn = conn
	defer conn.Close()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		var envelope slackEnvelope
		if err := conn.ReadJSON(&envelope); err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			log.Printf("[slack] read error: %v", err)
			return err
		}

		// Acknowledge the envelope immediately.
		if envelope.EnvelopeID != "" {
			ack := map[string]string{"envelope_id": envelope.EnvelopeID}
			if err := conn.WriteJSON(ack); err != nil {
				log.Printf("[slack] ack error: %v", err)
			}
		}

		if envelope.Type == "events_api" {
			var event slackEventWrapper
			if err := json.Unmarshal(envelope.Payload, &event); err != nil {
				log.Printf("[slack] unmarshal error: %v", err)
				continue
			}
			if event.Event.Type == "message" && event.Event.SubType == "" && event.Event.BotID == "" {
				s.handler(IncomingMessage{
					ChannelID: "slack",
					ChatID:    event.Event.Channel,
					SenderID:  event.Event.User,
					Text:      event.Event.Text,
					Timestamp: time.Now(),
				})
			}
		}
	}
}

// Stop closes the WebSocket connection.
func (s *SlackChannel) Stop() error {
	if s.cancelFunc != nil {
		s.cancelFunc()
	}
	if s.conn != nil {
		return s.conn.Close()
	}
	return nil
}

// SendMessage posts a message to a Slack channel via the Web API.
func (s *SlackChannel) SendMessage(chatID string, text string) error {
	body, _ := json.Marshal(map[string]string{
		"channel": chatID,
		"text":    text,
	})
	req, err := http.NewRequest(http.MethodPost, "https://slack.com/api/chat.postMessage", strings.NewReader(string(body)))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+s.botToken)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("slack API request failed: %w", err)
	}
	defer resp.Body.Close()

	var result struct {
		OK    bool   `json:"ok"`
		Error string `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return err
	}
	if !result.OK {
		return fmt.Errorf("slack API error: %s", result.Error)
	}
	return nil
}

func (s *SlackChannel) openConnection() (string, error) {
	req, err := http.NewRequest(http.MethodPost, "https://slack.com/api/apps.connections.open", nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+s.appToken)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var result struct {
		OK  bool   `json:"ok"`
		URL string `json:"url"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}
	if !result.OK {
		return "", fmt.Errorf("apps.connections.open failed")
	}
	return result.URL, nil
}

type slackEnvelope struct {
	EnvelopeID string          `json:"envelope_id"`
	Type       string          `json:"type"`
	Payload    json.RawMessage `json:"payload"`
}

type slackEventWrapper struct {
	Event struct {
		Type    string `json:"type"`
		SubType string `json:"subtype"`
		Channel string `json:"channel"`
		User    string `json:"user"`
		Text    string `json:"text"`
		BotID   string `json:"bot_id"`
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

	ch, err := channels.NewSlackChannel(func(msg channels.IncomingMessage) {
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
