# DingTalk Channel Adapter

DingTalk bot adapter using the Stream (WebSocket) protocol.

## Dependencies

```bash
npm install ws
npm install -D @types/ws
```

## Environment Variables

```
DINGTALK_CLIENT_ID=your-client-id
DINGTALK_CLIENT_SECRET=your-client-secret
```

## Adapter

```typescript
import WebSocket from "ws";

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

// -- DingTalk implementation --

interface DingTalkConfig {
  clientId: string;
  clientSecret: string;
}

interface DingTalkStreamMessage {
  specVersion: string;
  type: string;
  headers: Record<string, string>;
  data: string;
}

class DingTalkAdapter implements ChannelAdapter {
  readonly name = "dingtalk";
  private ws: WebSocket | null = null;
  private handler: MessageHandler | null = null;
  private accessToken: string = "";
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly apiBase = "https://api.dingtalk.com";

  constructor(private config: DingTalkConfig) {}

  onMessage(handler: MessageHandler): void {
    this.handler = handler;
  }

  async start(): Promise<void> {
    this.accessToken = await this.getAccessToken();
    const endpoint = await this.getStreamEndpoint();
    this.connect(endpoint);
    console.log(`[${this.name}] Stream connection started`);
  }

  async stop(): Promise<void> {
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    console.log(`[${this.name}] Stream connection stopped`);
  }

  async sendMessage(channelId: string, message: OutgoingMessage): Promise<void> {
    await fetch(`${this.apiBase}/v1.0/robot/oToMessages/batchSend`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-acs-dingtalk-access-token": this.accessToken,
      },
      body: JSON.stringify({
        robotCode: this.config.clientId,
        userIds: [channelId],
        msgKey: "sampleText",
        msgParam: JSON.stringify({ content: message.text }),
      }),
    });
  }

  private connect(endpoint: string): void {
    this.ws = new WebSocket(endpoint);

    this.ws.on("open", () => {
      console.log(`[${this.name}] WebSocket connected`);
    });

    this.ws.on("message", async (data: Buffer) => {
      const raw: DingTalkStreamMessage = JSON.parse(data.toString());

      // Respond to system pings
      if (raw.type === "SYSTEM" && raw.headers?.topic === "ping") {
        this.ws?.send(JSON.stringify({ code: 200, headers: raw.headers, message: "OK", data: raw.data }));
        return;
      }

      if (raw.type !== "CALLBACK" || !this.handler) return;

      const payload = JSON.parse(raw.data);
      const incoming: IncomingMessage = {
        channelId: payload.conversationId ?? payload.senderStaffId ?? "",
        userId: payload.senderStaffId ?? "unknown",
        userName: payload.senderNick ?? "Unknown",
        text: payload.text?.content?.trim() ?? "",
        attachments: [],
        raw: payload,
      };

      const response = await this.handler(incoming);

      // Acknowledge the callback
      this.ws?.send(JSON.stringify({ code: 200, headers: raw.headers, message: "OK", data: response ? JSON.stringify({ content: response.text }) : "{}" }));
    });

    this.ws.on("close", () => {
      console.log(`[${this.name}] WebSocket closed, reconnecting in 5s...`);
      this.reconnectTimer = setTimeout(() => this.start(), 5000);
    });

    this.ws.on("error", (err: Error) => {
      console.error(`[${this.name}] WebSocket error:`, err.message);
    });
  }

  private async getAccessToken(): Promise<string> {
    const res = await fetch(`${this.apiBase}/v1.0/oauth2/accessToken`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ appKey: this.config.clientId, appSecret: this.config.clientSecret }),
    });
    const json = (await res.json()) as { accessToken: string };
    return json.accessToken;
  }

  private async getStreamEndpoint(): Promise<string> {
    const res = await fetch(`${this.apiBase}/v1.0/gateway/connections/open`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-acs-dingtalk-access-token": this.accessToken,
      },
      body: JSON.stringify({ clientId: this.config.clientId, clientSecret: this.config.clientSecret }),
    });
    const json = (await res.json()) as { endpoint: string; ticket: string };
    return `${json.endpoint}?ticket=${json.ticket}`;
  }
}
```

## Usage

```typescript
const adapter = new DingTalkAdapter({
  clientId: process.env.DINGTALK_CLIENT_ID!,
  clientSecret: process.env.DINGTALK_CLIENT_SECRET!,
});

adapter.onMessage(async (msg) => {
  console.log(`[{{PROJECT_NAME}}] ${msg.userName}: ${msg.text}`);
  return { text: `Echo: ${msg.text}` };
});

await adapter.start();
```
