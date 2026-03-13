# Telegram Channel Adapter

Telegram bot adapter using [grammY](https://grammy.dev/) with polling mode. Handles text messages and photos.

## Dependencies

```bash
npm install grammy
```

## Environment Variables

```
TELEGRAM_BOT_TOKEN=your-bot-token
```

## Adapter

```typescript
import { Bot, Context } from "grammy";

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

// -- Telegram implementation --

interface TelegramConfig {
  botToken: string;
}

class TelegramAdapter implements ChannelAdapter {
  readonly name = "telegram";
  private bot: Bot;
  private handler: MessageHandler | null = null;

  constructor(private config: TelegramConfig) {
    this.bot = new Bot(config.botToken);
  }

  onMessage(handler: MessageHandler): void {
    this.handler = handler;
  }

  async start(): Promise<void> {
    this.bot.on("message:text", async (ctx: Context) => {
      if (!this.handler || !ctx.message) return;
      const incoming = this.convertIncoming(ctx);
      const response = await this.handler(incoming);
      if (response) {
        await this.reply(ctx, response);
      }
    });

    this.bot.on("message:photo", async (ctx: Context) => {
      if (!this.handler || !ctx.message) return;
      const photo = ctx.message.photo;
      const largest = photo?.[photo.length - 1];
      const file = largest ? await ctx.api.getFile(largest.file_id) : null;
      const url = file
        ? `https://api.telegram.org/file/bot${this.config.botToken}/${file.file_path}`
        : "";

      const incoming: IncomingMessage = {
        channelId: String(ctx.message.chat.id),
        userId: String(ctx.message.from?.id ?? "unknown"),
        userName: ctx.message.from?.first_name ?? "Unknown",
        text: ctx.message.caption ?? "",
        attachments: url ? [{ type: "image", url }] : [],
        raw: ctx.message,
      };

      const response = await this.handler(incoming);
      if (response) {
        await this.reply(ctx, response);
      }
    });

    await this.bot.start();
    console.log(`[${this.name}] Bot started (polling)`);
  }

  async stop(): Promise<void> {
    await this.bot.stop();
    console.log(`[${this.name}] Bot stopped`);
  }

  async sendMessage(channelId: string, message: OutgoingMessage): Promise<void> {
    if (message.attachments?.length) {
      for (const att of message.attachments) {
        if (att.type === "image") {
          await this.bot.api.sendPhoto(channelId, att.url, {
            caption: att.caption,
          });
        }
      }
    }
    if (message.text) {
      await this.bot.api.sendMessage(channelId, message.text);
    }
  }

  private convertIncoming(ctx: Context): IncomingMessage {
    const msg = ctx.message!;
    return {
      channelId: String(msg.chat.id),
      userId: String(msg.from?.id ?? "unknown"),
      userName: msg.from?.first_name ?? "Unknown",
      text: msg.text ?? "",
      attachments: [],
      raw: msg,
    };
  }

  private async reply(ctx: Context, message: OutgoingMessage): Promise<void> {
    if (message.attachments?.length) {
      for (const att of message.attachments) {
        if (att.type === "image") {
          await ctx.replyWithPhoto(att.url, { caption: att.caption });
        }
      }
    }
    if (message.text) {
      await ctx.reply(message.text);
    }
  }
}
```

## Usage

```typescript
const adapter = new TelegramAdapter({
  botToken: process.env.TELEGRAM_BOT_TOKEN!,
});

adapter.onMessage(async (msg) => {
  console.log(`[{{PROJECT_NAME}}] ${msg.userName}: ${msg.text}`);
  return { text: `Echo: ${msg.text}` };
});

await adapter.start();
```
