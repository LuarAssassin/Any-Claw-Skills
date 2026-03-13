# Slack Channel Adapter

Slack bot adapter using [@slack/bolt](https://slack.dev/bolt-js/) with Socket Mode.

## Dependencies

```bash
npm install @slack/bolt
```

## Environment Variables

```
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_APP_TOKEN=xapp-your-app-token
SLACK_SIGNING_SECRET=your-signing-secret
```

## Adapter

```typescript
import { App, MessageEvent, SayFn } from "@slack/bolt";

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

// -- Slack implementation --

interface SlackConfig {
  botToken: string;
  appToken: string;
  signingSecret: string;
}

class SlackAdapter implements ChannelAdapter {
  readonly name = "slack";
  private app: App;
  private handler: MessageHandler | null = null;

  constructor(private config: SlackConfig) {
    this.app = new App({
      token: config.botToken,
      appToken: config.appToken,
      signingSecret: config.signingSecret,
      socketMode: true,
    });
  }

  onMessage(handler: MessageHandler): void {
    this.handler = handler;
  }

  async start(): Promise<void> {
    this.app.message(async ({ message, say }) => {
      if (!this.handler) return;
      const msg = message as MessageEvent & { text?: string; user?: string; files?: Array<{ url_private: string; mimetype: string }> };
      if (msg.subtype || !msg.text) return;

      const incoming: IncomingMessage = {
        channelId: msg.channel,
        userId: msg.user ?? "unknown",
        userName: msg.user ?? "unknown",
        text: msg.text,
        attachments: (msg.files ?? []).map((f) => ({
          type: f.mimetype.startsWith("image/") ? "image" : "file",
          url: f.url_private,
        })),
        raw: msg,
      };

      const response = await this.handler(incoming);
      if (response) {
        await this.reply(say, response);
      }
    });

    await this.app.start();
    console.log(`[${this.name}] Bot started (socket mode)`);
  }

  async stop(): Promise<void> {
    await this.app.stop();
    console.log(`[${this.name}] Bot stopped`);
  }

  async sendMessage(channelId: string, message: OutgoingMessage): Promise<void> {
    if (message.text) {
      await this.app.client.chat.postMessage({
        channel: channelId,
        text: message.text,
      });
    }
    if (message.attachments?.length) {
      for (const att of message.attachments) {
        await this.app.client.chat.postMessage({
          channel: channelId,
          text: att.caption ?? "",
          blocks: [
            {
              type: "image",
              image_url: att.url,
              alt_text: att.caption ?? "image",
            },
          ],
        });
      }
    }
  }

  private async reply(say: SayFn, message: OutgoingMessage): Promise<void> {
    if (message.text) {
      await say(message.text);
    }
  }
}
```

## Usage

```typescript
const adapter = new SlackAdapter({
  botToken: process.env.SLACK_BOT_TOKEN!,
  appToken: process.env.SLACK_APP_TOKEN!,
  signingSecret: process.env.SLACK_SIGNING_SECRET!,
});

adapter.onMessage(async (msg) => {
  console.log(`[{{PROJECT_NAME}}] ${msg.userName}: ${msg.text}`);
  return { text: `Echo: ${msg.text}` };
});

await adapter.start();
```
