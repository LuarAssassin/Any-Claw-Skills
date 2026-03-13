# CLI/REPL Channel Adapter (Go)

CLI channel adapter for local development and testing. Reads user input from stdin via `bufio.Scanner` and writes responses to stdout. Uses only the Go standard library. No external dependencies.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `CLI_PROMPT` | Input prompt string (default: `> `) |

## Code

```go
package channels

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"time"
)

// CLIChannel implements the Channel interface for terminal REPL interaction.
type CLIChannel struct {
	prompt     string
	handler    MessageHandler
	cancelFunc context.CancelFunc
}

// NewCLIChannel creates a new CLI adapter.
func NewCLIChannel(handler MessageHandler) (*CLIChannel, error) {
	prompt := os.Getenv("CLI_PROMPT")
	if prompt == "" {
		prompt = "> "
	}
	return &CLIChannel{
		prompt:  prompt,
		handler: handler,
	}, nil
}

// Start reads lines from stdin and dispatches them as messages.
func (c *CLIChannel) Start(ctx context.Context) error {
	ctx, c.cancelFunc = context.WithCancel(ctx)
	scanner := bufio.NewScanner(os.Stdin)

	fmt.Println("{{PROJECT_NAME}} CLI - type a message or Ctrl+C to exit")
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		fmt.Print(c.prompt)
		if !scanner.Scan() {
			break
		}
		text := scanner.Text()
		if text == "" {
			continue
		}
		c.handler(IncomingMessage{
			ChannelID: "cli",
			ChatID:    "local",
			SenderID:  "user",
			Text:      text,
			Timestamp: time.Now(),
		})
	}
	return scanner.Err()
}

// Stop cancels the read loop.
func (c *CLIChannel) Stop() error {
	if c.cancelFunc != nil {
		c.cancelFunc()
	}
	return nil
}

// SendMessage prints text to stdout.
func (c *CLIChannel) SendMessage(chatID string, text string) error {
	fmt.Println(text)
	return nil
}
```

## Usage

```go
package main

import (
	"context"
	"os"
	"os/signal"

	"{{PROJECT_NAME}}/channels"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	var ch *channels.CLIChannel
	ch, err := channels.NewCLIChannel(func(msg channels.IncomingMessage) {
		// Echo the message back.
		ch.SendMessage(msg.ChatID, "You said: "+msg.Text)
	})
	if err != nil {
		os.Exit(1)
	}
	ch.Start(ctx)
}
```
