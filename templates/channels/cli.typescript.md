# CLI / REPL Channel Adapter

Command-line REPL adapter using Node.js readline. Supports streaming display of responses.

## Dependencies

None -- uses Node.js built-in modules only.

## Adapter

```typescript
import * as readline from "node:readline";
import { stdin, stdout } from "node:process";

// -- Shared interface (same across all channel adapters) --

interface IncomingMessage {
  channelId: string;
  userId: string;
  userName: string;
  text: string;
  attachments: Array<{ type: string; url: string }>;
  raw: unknown;
}

interface OutgoingMessage {
  text: string;
  attachments?: Array<{ type: string; url: string; caption?: string }>;
}

interface MessageHandler {
  (message: IncomingMessage): Promise<OutgoingMessage | void>;
}

interface ChannelAdapter {
  readonly name: string;
  start(): Promise<void>;
  stop(): Promise<void>;
  sendMessage(channelId: string, message: OutgoingMessage): Promise<void>;
  onMessage(handler: MessageHandler): void;
}

// -- CLI implementation --

class CLIAdapter implements ChannelAdapter {
  readonly name = "cli";
  private rl: readline.Interface | null = null;
  private handler: MessageHandler | null = null;
  private running = false;

  onMessage(handler: MessageHandler): void {
    this.handler = handler;
  }

  async start(): Promise<void> {
    this.running = true;
    this.rl = readline.createInterface({ input: stdin, output: stdout });

    console.log("{{PROJECT_NAME}} CLI ready. Type a message or 'exit' to quit.\n");
    this.prompt();

    this.rl.on("line", async (line: string) => {
      const text = line.trim();
      if (!text) {
        this.prompt();
        return;
      }
      if (text.toLowerCase() === "exit") {
        await this.stop();
        return;
      }
      if (!this.handler) {
        this.prompt();
        return;
      }

      const incoming: IncomingMessage = {
        channelId: "cli",
        userId: "local-user",
        userName: process.env.USER ?? "user",
        text,
        attachments: [],
        raw: { line },
      };

      const response = await this.handler(incoming);
      if (response) {
        this.streamOutput(response.text);
      }
      this.prompt();
    });

    this.rl.on("close", () => {
      this.running = false;
    });
  }

  async stop(): Promise<void> {
    this.running = false;
    if (this.rl) {
      this.rl.close();
      this.rl = null;
    }
    console.log("\nGoodbye.");
  }

  async sendMessage(_channelId: string, message: OutgoingMessage): Promise<void> {
    this.streamOutput(message.text);
  }

  private prompt(): void {
    if (this.running && this.rl) {
      this.rl.prompt();
    }
  }

  private streamOutput(text: string): void {
    stdout.write("\n");
    for (const char of text) {
      stdout.write(char);
    }
    stdout.write("\n\n");
  }
}
```

## Usage

```typescript
const adapter = new CLIAdapter();

adapter.onMessage(async (msg) => {
  // Replace this with your actual agent logic
  return { text: `[{{PROJECT_NAME}}] You said: ${msg.text}` };
});

await adapter.start();
```
