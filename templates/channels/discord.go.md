# Discord Channel Adapter (Go)

Discord bot channel adapter using the Gateway WebSocket API (v10). Connects to the Discord gateway, maintains a heartbeat, and handles `MESSAGE_CREATE` events. Uses only the Go standard library (`net/http`, `encoding/json`, `nhooyr.io/websocket` is avoided in favor of `golang.org/x/net/websocket` or raw upgrade -- this template uses `gorilla/websocket` as the single dependency since Go's stdlib has no WebSocket client).

**Note:** Discord's gateway requires a WebSocket client. Go's standard library does not include one. This template uses a minimal vendorable approach with `golang.org/x/net/websocket` or you can swap in `gorilla/websocket`. The code below uses `gorilla/websocket` as the dependency.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DISCORD_BOT_TOKEN` | Bot token from Discord Developer Portal |

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
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// DiscordChannel implements the Channel interface for the Discord Gateway.
type DiscordChannel struct {
	token      string
	handler    MessageHandler
	conn       *websocket.Conn
	cancelFunc context.CancelFunc
	sessionID  string
	seq        *int64
	mu         sync.Mutex
}

// NewDiscordChannel creates a new Discord adapter from environment variables.
func NewDiscordChannel(handler MessageHandler) (*DiscordChannel, error) {
	token := os.Getenv("DISCORD_BOT_TOKEN")
	if token == "" {
		return nil, fmt.Errorf("DISCORD_BOT_TOKEN is required")
	}
	return &DiscordChannel{
		token:   token,
		handler: handler,
	}, nil
}

// Start connects to the Discord gateway and listens for messages.
func (d *DiscordChannel) Start(ctx context.Context) error {
	ctx, d.cancelFunc = context.WithCancel(ctx)

	gatewayURL, err := d.getGatewayURL()
	if err != nil {
		return fmt.Errorf("failed to get gateway URL: %w", err)
	}

	conn, _, err := websocket.DefaultDialer.DialContext(ctx, gatewayURL+"/?v=10&encoding=json", nil)
	if err != nil {
		return fmt.Errorf("websocket dial failed: %w", err)
	}
	d.conn = conn
	defer conn.Close()

	// Read Hello (opcode 10) to get heartbeat interval.
	var hello discordPayload
	if err := conn.ReadJSON(&hello); err != nil {
		return fmt.Errorf("failed to read hello: %w", err)
	}
	var helloData struct {
		HeartbeatInterval int `json:"heartbeat_interval"`
	}
	json.Unmarshal(hello.D, &helloData)
	interval := time.Duration(helloData.HeartbeatInterval) * time.Millisecond

	// Send Identify (opcode 2).
	identify := discordPayload{
		Op: 2,
		D: mustMarshal(map[string]interface{}{
			"token":   "Bot " + d.token,
			"intents": 1 << 9 | 1 << 15, // GUILD_MESSAGES | MESSAGE_CONTENT
			"properties": map[string]string{
				"os":      "linux",
				"browser": "{{PROJECT_NAME}}",
				"device":  "{{PROJECT_NAME}}",
			},
		}),
	}
	if err := conn.WriteJSON(identify); err != nil {
		return fmt.Errorf("identify failed: %w", err)
	}

	// Start heartbeat loop.
	go d.heartbeatLoop(ctx, conn, interval)

	// Read messages.
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		var payload discordPayload
		if err := conn.ReadJSON(&payload); err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			log.Printf("[discord] read error: %v", err)
			return err
		}
		if payload.S != nil {
			d.mu.Lock()
			d.seq = payload.S
			d.mu.Unlock()
		}
		if payload.T == "MESSAGE_CREATE" {
			var msg discordMessage
			if err := json.Unmarshal(payload.D, &msg); err != nil {
				log.Printf("[discord] unmarshal message: %v", err)
				continue
			}
			if msg.Author.Bot {
				continue
			}
			d.handler(IncomingMessage{
				ChannelID: "discord",
				ChatID:    msg.ChannelID,
				SenderID:  msg.Author.ID,
				Text:      msg.Content,
				Timestamp: time.Now(),
			})
		}
	}
}

// Stop closes the gateway connection.
func (d *DiscordChannel) Stop() error {
	if d.cancelFunc != nil {
		d.cancelFunc()
	}
	if d.conn != nil {
		return d.conn.Close()
	}
	return nil
}

// SendMessage sends a message to a Discord channel via the REST API.
func (d *DiscordChannel) SendMessage(chatID string, text string) error {
	body, _ := json.Marshal(map[string]string{"content": text})
	url := fmt.Sprintf("https://discord.com/api/v10/channels/%s/messages", chatID)
	req, err := http.NewRequest(http.MethodPost, url, strings.NewReader(string(body)))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bot "+d.token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("discord API returned %d", resp.StatusCode)
	}
	return nil
}

func (d *DiscordChannel) heartbeatLoop(ctx context.Context, conn *websocket.Conn, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			d.mu.Lock()
			seq := d.seq
			d.mu.Unlock()
			hb := discordPayload{Op: 1, D: mustMarshal(seq)}
			if err := conn.WriteJSON(hb); err != nil {
				log.Printf("[discord] heartbeat error: %v", err)
				return
			}
		}
	}
}

func mustMarshal(v interface{}) json.RawMessage {
	b, _ := json.Marshal(v)
	return b
}

type discordPayload struct {
	Op int              `json:"op"`
	D  json.RawMessage  `json:"d,omitempty"`
	S  *int64           `json:"s,omitempty"`
	T  string           `json:"t,omitempty"`
}

type discordMessage struct {
	ChannelID string `json:"channel_id"`
	Content   string `json:"content"`
	Author    struct {
		ID  string `json:"id"`
		Bot bool   `json:"bot"`
	} `json:"author"`
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

	ch, err := channels.NewDiscordChannel(func(msg channels.IncomingMessage) {
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
