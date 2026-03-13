# Telegram Channel Adapter (Go)

Telegram bot channel adapter using long-polling via the Bot API. Uses only the Go standard library (`net/http`, `encoding/json`). Polls `getUpdates` with a timeout to receive messages and sends replies via `sendMessage`.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Bot token from @BotFather |
| `TELEGRAM_POLL_TIMEOUT` | Long-poll timeout in seconds (default: `30`) |

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
	"strconv"
	"time"
)

// IncomingMessage is the canonical message format for {{PROJECT_NAME}}.
type IncomingMessage struct {
	ChannelID string
	ChatID    string
	SenderID  string
	Text      string
	Timestamp time.Time
}

// MessageHandler is called when the adapter receives a message.
type MessageHandler func(msg IncomingMessage)

// TelegramChannel implements the Channel interface for Telegram Bot API.
type TelegramChannel struct {
	token      string
	timeout    int
	baseURL    string
	client     *http.Client
	handler    MessageHandler
	cancelFunc context.CancelFunc
}

// NewTelegramChannel creates a new Telegram adapter from environment variables.
func NewTelegramChannel(handler MessageHandler) (*TelegramChannel, error) {
	token := os.Getenv("TELEGRAM_BOT_TOKEN")
	if token == "" {
		return nil, fmt.Errorf("TELEGRAM_BOT_TOKEN is required")
	}
	timeout := 30
	if v := os.Getenv("TELEGRAM_POLL_TIMEOUT"); v != "" {
		if t, err := strconv.Atoi(v); err == nil && t > 0 {
			timeout = t
		}
	}
	return &TelegramChannel{
		token:   token,
		timeout: timeout,
		baseURL: "https://api.telegram.org/bot" + token,
		client:  &http.Client{Timeout: time.Duration(timeout+10) * time.Second},
		handler: handler,
	}, nil
}

// Start begins long-polling for updates. Blocks until ctx is cancelled.
func (t *TelegramChannel) Start(ctx context.Context) error {
	ctx, t.cancelFunc = context.WithCancel(ctx)
	offset := 0
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		updates, err := t.getUpdates(ctx, offset)
		if err != nil {
			log.Printf("[telegram] poll error: %v", err)
			time.Sleep(2 * time.Second)
			continue
		}
		for _, u := range updates {
			if u.Message != nil && u.Message.Text != "" {
				t.handler(IncomingMessage{
					ChannelID: "telegram",
					ChatID:    strconv.FormatInt(u.Message.Chat.ID, 10),
					SenderID:  strconv.FormatInt(u.Message.From.ID, 10),
					Text:      u.Message.Text,
					Timestamp: time.Unix(int64(u.Message.Date), 0),
				})
			}
			offset = u.UpdateID + 1
		}
	}
}

// Stop cancels the polling loop.
func (t *TelegramChannel) Stop() error {
	if t.cancelFunc != nil {
		t.cancelFunc()
	}
	return nil
}

// SendMessage sends a text message to the given chat.
func (t *TelegramChannel) SendMessage(chatID string, text string) error {
	params := url.Values{}
	params.Set("chat_id", chatID)
	params.Set("text", text)
	resp, err := t.client.PostForm(t.baseURL+"/sendMessage", params)
	if err != nil {
		return fmt.Errorf("sendMessage request failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("sendMessage returned %d: %s", resp.StatusCode, body)
	}
	return nil
}

func (t *TelegramChannel) getUpdates(ctx context.Context, offset int) ([]tgUpdate, error) {
	reqURL := fmt.Sprintf("%s/getUpdates?offset=%d&timeout=%d", t.baseURL, offset, t.timeout)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, err
	}
	resp, err := t.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var result struct {
		OK     bool       `json:"ok"`
		Result []tgUpdate `json:"result"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	return result.Result, nil
}

type tgUpdate struct {
	UpdateID int        `json:"update_id"`
	Message  *tgMessage `json:"message"`
}

type tgMessage struct {
	Text string `json:"text"`
	Date int    `json:"date"`
	Chat struct {
		ID int64 `json:"id"`
	} `json:"chat"`
	From struct {
		ID int64 `json:"id"`
	} `json:"from"`
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

	ch, err := channels.NewTelegramChannel(func(msg channels.IncomingMessage) {
		fmt.Printf("[%s] %s: %s\n", msg.ChatID, msg.SenderID, msg.Text)
		// Echo back
		_ = ch.SendMessage(msg.ChatID, "You said: "+msg.Text)
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
