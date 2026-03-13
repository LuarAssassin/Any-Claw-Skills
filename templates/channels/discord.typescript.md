# Discord Channel Adapter

Discord bot adapter using [discord.js](https://discord.js.org/) with event handling and slash commands.

## Dependencies

```bash
npm install discord.js
```

## Environment Variables

```
DISCORD_BOT_TOKEN=your-bot-token
DISCORD_APPLICATION_ID=your-app-id
```

## Adapter

```typescript
import {
  Client,
  GatewayIntentBits,
  Events,
  Message,
  Interaction,
  REST,
  Routes,
  SlashCommandBuilder,
  TextChannel,
} from "discord.js";

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

// -- Discord implementation --

interface DiscordConfig {
  botToken: string;
  applicationId: string;
  slashCommands?: Array<{ name: string; description: string }>;
}

class DiscordAdapter implements ChannelAdapter {
  readonly name = "discord";
  private client: Client;
  private handler: MessageHandler | null = null;

  constructor(private config: DiscordConfig) {
    this.client = new Client({
      intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent,
        GatewayIntentBits.DirectMessages,
      ],
    });
  }

  onMessage(handler: MessageHandler): void {
    this.handler = handler;
  }

  async start(): Promise<void> {
    await this.registerSlashCommands();

    this.client.on(Events.MessageCreate, async (message: Message) => {
      if (message.author.bot || !this.handler) return;

      const incoming = this.convertMessage(message);
      const response = await this.handler(incoming);
      if (response) {
        await this.sendToChannel(message.channel as TextChannel, response);
      }
    });

    this.client.on(Events.InteractionCreate, async (interaction: Interaction) => {
      if (!interaction.isChatInputCommand() || !this.handler) return;

      const incoming: IncomingMessage = {
        channelId: interaction.channelId,
        userId: interaction.user.id,
        userName: interaction.user.username,
        text: `/${interaction.commandName} ${interaction.options.data.map((o) => o.value).join(" ")}`.trim(),
        attachments: [],
        raw: interaction,
      };

      await interaction.deferReply();
      const response = await this.handler(incoming);
      if (response) {
        await interaction.editReply(response.text);
      }
    });

    await this.client.login(this.config.botToken);
    console.log(`[${this.name}] Bot started as ${this.client.user?.tag}`);
  }

  async stop(): Promise<void> {
    await this.client.destroy();
    console.log(`[${this.name}] Bot stopped`);
  }

  async sendMessage(channelId: string, message: OutgoingMessage): Promise<void> {
    const channel = await this.client.channels.fetch(channelId);
    if (channel && channel.isTextBased() && "send" in channel) {
      await this.sendToChannel(channel as TextChannel, message);
    }
  }

  private convertMessage(message: Message): IncomingMessage {
    return {
      channelId: message.channelId,
      userId: message.author.id,
      userName: message.author.username,
      text: message.content,
      attachments: message.attachments.map((att) => ({
        type: att.contentType?.startsWith("image/") ? "image" : "file",
        url: att.url,
      })),
      raw: message,
    };
  }

  private async sendToChannel(channel: TextChannel, message: OutgoingMessage): Promise<void> {
    const files = message.attachments?.map((att) => att.url) ?? [];
    await channel.send({ content: message.text, files });
  }

  private async registerSlashCommands(): Promise<void> {
    const commands = this.config.slashCommands ?? [];
    if (commands.length === 0) return;

    const rest = new REST().setToken(this.config.botToken);
    const body = commands.map((cmd) =>
      new SlashCommandBuilder().setName(cmd.name).setDescription(cmd.description).toJSON()
    );

    await rest.put(Routes.applicationCommands(this.config.applicationId), { body });
    console.log(`[${this.name}] Registered ${commands.length} slash command(s)`);
  }
}
```

## Usage

```typescript
const adapter = new DiscordAdapter({
  botToken: process.env.DISCORD_BOT_TOKEN!,
  applicationId: process.env.DISCORD_APPLICATION_ID!,
  slashCommands: [
    { name: "ask", description: "Ask {{PROJECT_NAME}} a question" },
  ],
});

adapter.onMessage(async (msg) => {
  console.log(`[{{PROJECT_NAME}}] ${msg.userName}: ${msg.text}`);
  return { text: `Echo: ${msg.text}` };
});

await adapter.start();
```
