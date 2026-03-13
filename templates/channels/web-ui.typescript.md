# Web Chat UI Channel Adapter

Web-based chat interface with Express server, WebSocket for real-time messaging, and Server-Sent Events (SSE) for streaming responses. Includes a self-contained HTML/CSS/JS chat frontend.

## Dependencies

```bash
npm install express ws
npm install -D @types/express @types/ws
```

## Environment Variables

```
WEB_UI_PORT=3000
```

## Adapter

```typescript
import express, { Request, Response } from "express";
import http from "node:http";
import { WebSocketServer, WebSocket } from "ws";
import crypto from "node:crypto";

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

// -- Web UI implementation --

interface WebUIConfig {
  port: number;
  title?: string;
}

interface ConnectedClient {
  ws: WebSocket;
  userId: string;
  sessionId: string;
}

class WebUIAdapter implements ChannelAdapter {
  readonly name = "web-ui";
  private app: express.Express;
  private server: http.Server | null = null;
  private wss: WebSocketServer | null = null;
  private handler: MessageHandler | null = null;
  private clients = new Map<string, ConnectedClient>();
  private sseClients = new Map<string, Response>();

  constructor(private config: WebUIConfig) {
    this.app = express();
    this.app.use(express.json());
    this.setupRoutes();
  }

  onMessage(handler: MessageHandler): void {
    this.handler = handler;
  }

  async start(): Promise<void> {
    return new Promise((resolve) => {
      this.server = http.createServer(this.app);
      this.wss = new WebSocketServer({ server: this.server });

      this.wss.on("connection", (ws: WebSocket) => {
        const sessionId = crypto.randomUUID();
        const client: ConnectedClient = { ws, userId: sessionId, sessionId };
        this.clients.set(sessionId, client);

        ws.send(JSON.stringify({ type: "connected", sessionId }));

        ws.on("message", async (data: Buffer) => {
          const parsed = JSON.parse(data.toString());
          if (parsed.type !== "message" || !this.handler) return;

          const incoming: IncomingMessage = {
            channelId: sessionId,
            userId: sessionId,
            userName: parsed.userName ?? "User",
            text: parsed.text,
            attachments: [],
            raw: parsed,
          };

          const response = await this.handler(incoming);
          if (response) {
            ws.send(JSON.stringify({ type: "message", text: response.text }));
          }
        });

        ws.on("close", () => {
          this.clients.delete(sessionId);
        });
      });

      // SSE streaming endpoint
      this.app.get("/api/stream/:sessionId", (req: Request, res: Response) => {
        const { sessionId } = req.params;
        res.writeHead(200, {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          Connection: "keep-alive",
        });
        this.sseClients.set(sessionId, res);
        req.on("close", () => this.sseClients.delete(sessionId));
      });

      // REST message endpoint (alternative to WebSocket)
      this.app.post("/api/message", async (req: Request, res: Response) => {
        if (!this.handler) {
          res.status(503).json({ error: "No handler configured" });
          return;
        }
        const { text, userName, sessionId } = req.body;
        const sid = sessionId ?? crypto.randomUUID();

        const incoming: IncomingMessage = {
          channelId: sid,
          userId: sid,
          userName: userName ?? "User",
          text,
          attachments: [],
          raw: req.body,
        };

        const response = await this.handler(incoming);

        // Stream via SSE if client is connected
        const sseRes = this.sseClients.get(sid);
        if (sseRes && response) {
          for (const chunk of this.chunkText(response.text, 10)) {
            sseRes.write(`data: ${JSON.stringify({ text: chunk })}\n\n`);
          }
          sseRes.write(`data: ${JSON.stringify({ done: true })}\n\n`);
        }

        res.json({ sessionId: sid, text: response?.text ?? "" });
      });

      this.server.listen(this.config.port, () => {
        console.log(`[${this.name}] Server listening on http://localhost:${this.config.port}`);
        resolve();
      });
    });
  }

  async stop(): Promise<void> {
    for (const [, client] of this.clients) {
      client.ws.close();
    }
    this.clients.clear();
    this.sseClients.clear();

    return new Promise((resolve, reject) => {
      if (!this.server) return resolve();
      this.server.close((err) => (err ? reject(err) : resolve()));
      console.log(`[${this.name}] Server stopped`);
    });
  }

  async sendMessage(channelId: string, message: OutgoingMessage): Promise<void> {
    const client = this.clients.get(channelId);
    if (client && client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(JSON.stringify({ type: "message", text: message.text }));
    }
  }

  private chunkText(text: string, size: number): string[] {
    const chunks: string[] = [];
    for (let i = 0; i < text.length; i += size) {
      chunks.push(text.slice(i, i + size));
    }
    return chunks;
  }

  private setupRoutes(): void {
    const title = this.config.title ?? "{{PROJECT_NAME}}";

    this.app.get("/", (_req: Request, res: Response) => {
      res.type("html").send(`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${title}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f5f5f5; height: 100vh; display: flex; flex-direction: column; }
  .header { background: #1a1a2e; color: #fff; padding: 16px 24px; font-size: 18px; font-weight: 600; }
  .messages { flex: 1; overflow-y: auto; padding: 24px; display: flex; flex-direction: column; gap: 12px; }
  .message { max-width: 70%; padding: 12px 16px; border-radius: 12px; line-height: 1.5; white-space: pre-wrap; word-break: break-word; }
  .message.user { align-self: flex-end; background: #1a1a2e; color: #fff; border-bottom-right-radius: 4px; }
  .message.bot { align-self: flex-start; background: #fff; color: #1a1a2e; border: 1px solid #e0e0e0; border-bottom-left-radius: 4px; }
  .message.bot.streaming { opacity: 0.8; }
  .input-area { padding: 16px 24px; background: #fff; border-top: 1px solid #e0e0e0; display: flex; gap: 12px; }
  .input-area input { flex: 1; padding: 12px 16px; border: 1px solid #ddd; border-radius: 8px; font-size: 14px; outline: none; }
  .input-area input:focus { border-color: #1a1a2e; }
  .input-area button { padding: 12px 24px; background: #1a1a2e; color: #fff; border: none; border-radius: 8px; cursor: pointer; font-size: 14px; }
  .input-area button:hover { background: #16213e; }
  .input-area button:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
</head>
<body>
<div class="header">${title}</div>
<div class="messages" id="messages"></div>
<div class="input-area">
  <input type="text" id="input" placeholder="Type a message..." autocomplete="off">
  <button id="send">Send</button>
</div>
<script>
const messagesEl = document.getElementById("messages");
const inputEl = document.getElementById("input");
const sendBtn = document.getElementById("send");

let ws;
let sessionId = null;

function addMessage(text, sender) {
  const div = document.createElement("div");
  div.className = "message " + sender;
  div.textContent = text;
  messagesEl.appendChild(div);
  messagesEl.scrollTop = messagesEl.scrollHeight;
  return div;
}

function connect() {
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  ws = new WebSocket(proto + "//" + location.host);

  ws.onopen = () => console.log("Connected");

  ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    if (data.type === "connected") {
      sessionId = data.sessionId;
    } else if (data.type === "message") {
      addMessage(data.text, "bot");
      sendBtn.disabled = false;
      inputEl.disabled = false;
      inputEl.focus();
    }
  };

  ws.onclose = () => {
    console.log("Disconnected, reconnecting...");
    setTimeout(connect, 2000);
  };
}

function send() {
  const text = inputEl.value.trim();
  if (!text || !ws || ws.readyState !== WebSocket.OPEN) return;
  addMessage(text, "user");
  ws.send(JSON.stringify({ type: "message", text, sessionId }));
  inputEl.value = "";
  sendBtn.disabled = true;
  inputEl.disabled = true;
}

sendBtn.addEventListener("click", send);
inputEl.addEventListener("keydown", (e) => { if (e.key === "Enter") send(); });

connect();
inputEl.focus();
</script>
</body>
</html>`);
    });
  }
}
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `port` | `number` | -- | Server port |
| `title` | `string` | `"{{PROJECT_NAME}}"` | Page title and header text |

## Usage

```typescript
const adapter = new WebUIAdapter({
  port: Number(process.env.WEB_UI_PORT ?? 3000),
  title: "{{PROJECT_NAME}} Chat",
});

adapter.onMessage(async (msg) => {
  console.log(`[{{PROJECT_NAME}}] ${msg.userName}: ${msg.text}`);
  return { text: `Echo: ${msg.text}` };
});

await adapter.start();
// Open http://localhost:3000 in your browser
```
