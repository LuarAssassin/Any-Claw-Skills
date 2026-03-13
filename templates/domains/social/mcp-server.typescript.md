# MCP Server: Social Media (TypeScript)

MCP SDK server exposing social media tools as MCP resources and tools.

## Dependencies

```bash
npm install @modelcontextprotocol/sdk zod
```

## Generated File: `server/socialMcp.ts`

```typescript
/**
 * MCP server for {{PROJECT_NAME}} social media tools.
 *
 * Exposes feed monitoring, content curation, trend analysis, and post
 * scheduling as MCP tools via the official MCP SDK.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

import {
  feedMonitor,
  contentCurator,
  trendAnalyzer,
  postScheduler,
  type FeedResults,
  type CuratedContent,
  type TrendReport,
  type ScheduleResult,
} from "../tools/socialTools.js";

// ---------------------------------------------------------------------------
// Server setup
// ---------------------------------------------------------------------------

const server = new McpServer({
  name: "{{PROJECT_NAME}} Social Media",
  version: "{{VERSION}}",
});

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

server.tool(
  "monitor_feed",
  "Monitor a social media feed for posts matching specified keywords. " +
    "Returns matched posts with engagement metrics.",
  {
    platform: z.string().describe("Target platform: twitter, linkedin, instagram, mastodon"),
    keywords: z.array(z.string()).describe("Keywords or hashtags to monitor"),
  },
  async ({ platform, keywords }): Promise<{ content: Array<{ type: "text"; text: string }> }> => {
    const result: FeedResults = await feedMonitor(platform, keywords);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  },
);

server.tool(
  "curate_content",
  "Curate top content on a given topic across all configured platforms. " +
    "Scores posts by relevance and engagement, returns items with suggested actions.",
  {
    topic: z.string().describe("Topic or theme to curate content for"),
    count: z.number().int().min(1).max(50).default(10).describe("Max items to return"),
  },
  async ({ topic, count }): Promise<{ content: Array<{ type: "text"; text: string }> }> => {
    const result: CuratedContent = await contentCurator(topic, count);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  },
);

server.tool(
  "analyze_trends",
  "Analyze trending topics on a platform within a category. " +
    "Returns trends ranked by volume with velocity indicators.",
  {
    platform: z.string().describe("Platform to analyze trends on"),
    category: z.string().default("general").describe("Topic category filter"),
  },
  async ({ platform, category }): Promise<{ content: Array<{ type: "text"; text: string }> }> => {
    const result: TrendReport = await trendAnalyzer(platform, category);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  },
);

server.tool(
  "schedule_post",
  "Schedule a post for future publication on a platform. " +
    "Validates the time and returns confirmation with scheduled post ID.",
  {
    platform: z.string().describe("Platform to schedule the post on"),
    content: z.string().describe("Post content text"),
    schedule_time: z.string().describe("ISO-8601 datetime for publication"),
  },
  async ({ platform, content, schedule_time }): Promise<{ content: Array<{ type: "text"; text: string }> }> => {
    const result: ScheduleResult = await postScheduler(platform, content, schedule_time);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  },
);

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

server.resource(
  "platforms",
  "social://platforms",
  async (): Promise<{ contents: Array<{ uri: string; mimeType: string; text: string }> }> => {
    const platforms = ["twitter", "linkedin", "instagram", "mastodon"];
    const data = {
      platforms: platforms.map((name) => ({
        name,
        configured: true,
      })),
      queriedAt: new Date().toISOString(),
    };
    return {
      contents: [
        {
          uri: "social://platforms",
          mimeType: "application/json",
          text: JSON.stringify(data, null, 2),
        },
      ],
    };
  },
);

server.resource(
  "trends",
  "social://trends/{platform}",
  async (uri): Promise<{ contents: Array<{ uri: string; mimeType: string; text: string }> }> => {
    const platform = uri.pathname.split("/").pop() ?? "twitter";
    const result = await trendAnalyzer(platform, "general");
    return {
      contents: [
        {
          uri: uri.toString(),
          mimeType: "application/json",
          text: JSON.stringify(result, null, 2),
        },
      ],
    };
  },
);

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  console.error(`Starting {{PROJECT_NAME}} Social MCP server`);
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Server connected via stdio");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Project name used in server metadata and logging |
| `{{VERSION}}` | Semantic version string (e.g. "1.0.0") |
