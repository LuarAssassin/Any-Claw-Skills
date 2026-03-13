# WhatsApp Channel Adapter

WhatsApp Cloud API adapter using Express for webhook handling.

## Dependencies

```bash
npm install express
npm install -D @types/express
```

## Environment Variables

```
WHATSAPP_API_TOKEN=your-api-token
WHATSAPP_PHONE_NUMBER_ID=your-phone-number-id
WHATSAPP_VERIFY_TOKEN=your-webhook-verify-token
WHATSAPP_WEBHOOK_PORT=3000
```

## Adapter

```typescript
import express, { Request, Response } from "express";
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

// -- WhatsApp implementation --

interface WhatsAppConfig {
  apiToken: string;
  phoneNumberId: string;
  verifyToken: string;
  port: number;
}

class WhatsAppAdapter implements ChannelAdapter {
  readonly name = "whatsapp";
  private app: express.Express;
  private server: http.Server | null = null;
  private handler: MessageHandler | null = null;
  private readonly apiBase = "https://graph.facebook.com/v18.0";

  constructor(private config: WhatsAppConfig) {
    this.app = express();
    this.app.use(express.json());
    this.setupRoutes();
  }

  onMessage(handler: MessageHandler): void {
    this.handler = handler;
  }

  async start(): Promise<void> {
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
    if (message.text) {
      await this.callApi(channelId, {
        messaging_product: "whatsapp",
        to: channelId,
        type: "text",
        text: { body: message.text },
      });
    }

    if (message.attachments?.length) {
      for (const att of message.attachments) {
        if (att.type === "image") {
          await this.callApi(channelId, {
            messaging_product: "whatsapp",
            to: channelId,
            type: "image",
            image: { link: att.url, caption: att.caption },
          });
        }
      }
    }
  }

  private setupRoutes(): void {
    // Webhook verification (GET)
    this.app.get("/webhook", (req: Request, res: Response) => {
      const mode = req.query["hub.mode"];
      const token = req.query["hub.verify_token"];
      const challenge = req.query["hub.challenge"];

      if (mode === "subscribe" && token === this.config.verifyToken) {
        res.status(200).send(challenge);
      } else {
        res.sendStatus(403);
      }
    });

    // Incoming messages (POST)
    this.app.post("/webhook", async (req: Request, res: Response) => {
      res.sendStatus(200);
      if (!this.handler) return;

      const body = req.body;
      const entry = body?.entry?.[0];
      const changes = entry?.changes?.[0];
      const value = changes?.value;
      const msg = value?.messages?.[0];
      if (!msg) return;

      const contact = value.contacts?.[0];
      const incoming: IncomingMessage = {
        channelId: msg.from,
        userId: msg.from,
        userName: contact?.profile?.name ?? msg.from,
        text: msg.text?.body ?? "",
        attachments: this.extractAttachments(msg),
        raw: msg,
      };

      const response = await this.handler(incoming);
      if (response) {
        await this.sendMessage(incoming.channelId, response);
      }
    });
  }

  private extractAttachments(msg: Record<string, unknown>): Array<{ type: string; url: string }> {
    const attachments: Array<{ type: string; url: string }> = [];
    if (msg.type === "image" && msg.image) {
      const image = msg.image as { id: string };
      attachments.push({ type: "image", url: `media:${image.id}` });
    }
    return attachments;
  }

  private async callApi(to: string, payload: unknown): Promise<void> {
    const url = `${this.apiBase}/${this.config.phoneNumberId}/messages`;
    await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.config.apiToken}`,
      },
      body: JSON.stringify(payload),
    });
  }
}
```

## Usage

```typescript
const adapter = new WhatsAppAdapter({
  apiToken: process.env.WHATSAPP_API_TOKEN!,
  phoneNumberId: process.env.WHATSAPP_PHONE_NUMBER_ID!,
  verifyToken: process.env.WHATSAPP_VERIFY_TOKEN!,
  port: Number(process.env.WHATSAPP_WEBHOOK_PORT ?? 3000),
});

adapter.onMessage(async (msg) => {
  console.log(`[{{PROJECT_NAME}}] ${msg.userName}: ${msg.text}`);
  return { text: `Echo: ${msg.text}` };
});

await adapter.start();
```
