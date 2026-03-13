# Feishu/Lark Channel Adapter

Feishu (Lark) bot adapter using event subscription with webhook verification.

## Dependencies

```bash
npm install express crypto
npm install -D @types/express
```

## Environment Variables

```
FEISHU_APP_ID=your-app-id
FEISHU_APP_SECRET=your-app-secret
FEISHU_VERIFICATION_TOKEN=your-verification-token
FEISHU_ENCRYPT_KEY=your-encrypt-key
FEISHU_WEBHOOK_PORT=3000
```

## Adapter

```typescript
import express, { Request, Response } from "express";
import crypto from "node:crypto";
import http from "node:http";

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

// -- Feishu implementation --

interface FeishuConfig {
  appId: string;
  appSecret: string;
  verificationToken: string;
  encryptKey?: string;
  port: number;
}

class FeishuAdapter implements ChannelAdapter {
  readonly name = "feishu";
  private app: express.Express;
  private server: http.Server | null = null;
  private handler: MessageHandler | null = null;
  private tenantAccessToken: string = "";
  private tokenExpiry: number = 0;
  private readonly apiBase = "https://open.feishu.cn/open-apis";
  private processedIds = new Set<string>();

  constructor(private config: FeishuConfig) {
    this.app = express();
    this.app.use(express.json());
    this.setupRoutes();
  }

  onMessage(handler: MessageHandler): void {
    this.handler = handler;
  }

  async start(): Promise<void> {
    await this.refreshToken();
    return new Promise((resolve) => {
      this.server = this.app.listen(this.config.port, () => {
        console.log(`[${this.name}] Webhook listening on port ${this.config.port}`);
        resolve();
      });
    });
  }

  async stop(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.server) return resolve();
      this.server.close((err) => (err ? reject(err) : resolve()));
      console.log(`[${this.name}] Webhook stopped`);
    });
  }

  async sendMessage(channelId: string, message: OutgoingMessage): Promise<void> {
    await this.ensureToken();
    await fetch(`${this.apiBase}/im/v1/messages?receive_id_type=chat_id`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.tenantAccessToken}`,
      },
      body: JSON.stringify({
        receive_id: channelId,
        msg_type: "text",
        content: JSON.stringify({ text: message.text }),
      }),
    });
  }

  private setupRoutes(): void {
    this.app.post("/webhook/event", async (req: Request, res: Response) => {
      const body = req.body;

      // URL verification challenge
      if (body.type === "url_verification") {
        res.json({ challenge: body.challenge });
        return;
      }

      // Verify token
      if (body.header?.token !== this.config.verificationToken) {
        res.sendStatus(403);
        return;
      }

      res.sendStatus(200);

      // Deduplicate events
      const eventId = body.header?.event_id;
      if (eventId && this.processedIds.has(eventId)) return;
      if (eventId) {
        this.processedIds.add(eventId);
        setTimeout(() => this.processedIds.delete(eventId), 300_000);
      }

      if (!this.handler) return;

      const event = body.event;
      if (event?.message?.message_type !== "text") return;

      const content = JSON.parse(event.message.content ?? "{}");
      const incoming: IncomingMessage = {
        channelId: event.message.chat_id,
        userId: event.sender?.sender_id?.user_id ?? "unknown",
        userName: event.sender?.sender_id?.user_id ?? "Unknown",
        text: content.text ?? "",
        attachments: [],
        raw: body,
      };

      const response = await this.handler(incoming);
      if (response) {
        await this.sendMessage(incoming.channelId, response);
      }
    });
  }

  private async refreshToken(): Promise<void> {
    const res = await fetch(`${this.apiBase}/auth/v3/tenant_access_token/internal`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ app_id: this.config.appId, app_secret: this.config.appSecret }),
    });
    const json = (await res.json()) as { tenant_access_token: string; expire: number };
    this.tenantAccessToken = json.tenant_access_token;
    this.tokenExpiry = Date.now() + (json.expire - 300) * 1000;
  }

  private async ensureToken(): Promise<void> {
    if (Date.now() >= this.tokenExpiry) {
      await this.refreshToken();
    }
  }
}
```

## Usage

```typescript
const adapter = new FeishuAdapter({
  appId: process.env.FEISHU_APP_ID!,
  appSecret: process.env.FEISHU_APP_SECRET!,
  verificationToken: process.env.FEISHU_VERIFICATION_TOKEN!,
  encryptKey: process.env.FEISHU_ENCRYPT_KEY,
  port: Number(process.env.FEISHU_WEBHOOK_PORT ?? 3000),
});

adapter.onMessage(async (msg) => {
  console.log(`[{{PROJECT_NAME}}] ${msg.userName}: ${msg.text}`);
  return { text: `Echo: ${msg.text}` };
});

await adapter.start();
```
