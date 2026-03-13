# Smart Home MCP Server (TypeScript)

Model Context Protocol server for smart home tools using the [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk).

## Dependencies

```bash
npm install @modelcontextprotocol/sdk zod
```

## Generated File: `mcp-servers/smartHomeServer.ts`

```typescript
/**
 * Smart home MCP server for {{PROJECT_NAME}}.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

import {
  deviceControl,
  automationRules,
  energyMonitor,
  sceneManager,
} from "../tools/smartHome.js";

const server = new McpServer({
  name: "{{PROJECT_NAME}} Smart Home",
  version: "{{VERSION}}",
});

// ---------------------------------------------------------------------------
// Device control
// ---------------------------------------------------------------------------

server.tool(
  "control_device",
  "Control a smart home device (turn on/off, set brightness, adjust thermostat, etc.)",
  {
    device_id: z.string().describe("Device identifier, e.g. light_living_01"),
    action: z.string().describe("Action: turn_on, turn_off, set, toggle"),
    params: z.record(z.unknown()).optional().describe("Action parameters"),
  },
  async ({ device_id, action, params }) => {
    const result = await deviceControl(device_id, action, params ?? {});
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
  },
);

// ---------------------------------------------------------------------------
// Automation rules
// ---------------------------------------------------------------------------

server.tool(
  "manage_automation",
  "Create, read, update, or delete automation rules",
  {
    action: z.enum(["create", "get", "list", "update", "delete"]),
    rule_id: z.string().optional().describe("Rule ID (for get/update/delete)"),
    name: z.string().optional().describe("Rule name (for create)"),
    trigger: z
      .object({
        type: z.enum(["time", "device_state", "sunrise", "sunset", "geofence", "webhook"]),
        config: z.record(z.unknown()).default({}),
      })
      .optional(),
    conditions: z
      .array(
        z.object({
          deviceId: z.string().nullish(),
          attribute: z.string(),
          operator: z.enum(["eq", "ne", "gt", "lt", "gte", "lte"]),
          value: z.unknown(),
        }),
      )
      .optional(),
    actions: z
      .array(
        z.object({
          deviceId: z.string(),
          action: z.string(),
          params: z.record(z.unknown()).default({}),
        }),
      )
      .optional(),
    enabled: z.boolean().default(true),
  },
  async ({ action, rule_id, name, trigger, conditions, actions, enabled }) => {
    const result = await automationRules(action, {
      ruleId: rule_id,
      name,
      trigger,
      conditions,
      actions,
      enabled,
    });
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
  },
);

// ---------------------------------------------------------------------------
// Energy monitoring
// ---------------------------------------------------------------------------

server.tool(
  "get_energy_usage",
  "Retrieve energy consumption data by period and optional device filter",
  {
    period: z.enum(["hour", "day", "week", "month", "year"]).default("day"),
    device_id: z.string().optional().describe("Device ID to filter by"),
  },
  async ({ period, device_id }) => {
    const result = await energyMonitor(period, device_id);
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
  },
);

// ---------------------------------------------------------------------------
// Scene management
// ---------------------------------------------------------------------------

server.tool(
  "manage_scene",
  "Manage multi-device scenes (create, activate, list, update, delete)",
  {
    action: z.enum(["create", "activate", "get", "list", "update", "delete"]),
    scene_id: z.string().optional().describe("Scene ID (for activate/get/update/delete)"),
    name: z.string().optional().describe("Scene name (for create)"),
    devices: z
      .array(z.record(z.unknown()))
      .optional()
      .describe("Device configs with device_id, action, params"),
  },
  async ({ action, scene_id, name, devices }) => {
    const result = await sceneManager(action, {
      sceneId: scene_id,
      name,
      devices,
    });
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
  },
);

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

server.resource(
  "devices",
  "smarthome://devices",
  async (uri) => {
    // Inline device listing without importing the hub directly
    const res = await fetch("{{HUB_URL}}/devices", {
      headers: { Authorization: "Bearer {{HUB_TOKEN}}" },
    });
    const data = (await res.json()) as { devices: Array<Record<string, unknown>> };
    const lines = data.devices.map((d) => {
      const status = d.online ? "online" : "offline";
      return `- ${d.name ?? d.id ?? "?"} [${d.category ?? "?"}] (${status})`;
    });
    return {
      contents: [
        {
          uri: uri.href,
          mimeType: "text/plain",
          text: lines.length > 0 ? lines.join("\n") : "No devices found.",
        },
      ],
    };
  },
);

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Smart home MCP server failed to start:", err);
  process.exit(1);
});
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project |
| `{{VERSION}}` | Server version string, e.g. `1.0.0` |
| `{{HUB_URL}}` | Hub API base URL |
| `{{HUB_TOKEN}}` | Hub API authentication token |

## Usage

```bash
# Build and run
npx tsx mcp-servers/smartHomeServer.ts

# Or compile first
npx tsc && node dist/mcp-servers/smartHomeServer.js
```
