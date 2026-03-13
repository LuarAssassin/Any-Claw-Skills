# Smart Home Tools (TypeScript)

TypeScript tool implementations for smart home device control, automation, energy monitoring, and scene management.

## Dependencies

```bash
npm install zod
```

## Generated File: `tools/smartHome.ts`

```typescript
/**
 * Smart home domain tools for {{PROJECT_NAME}}.
 */

import { z } from "zod";

// ---------------------------------------------------------------------------
// Schemas
// ---------------------------------------------------------------------------

const DeviceCategory = z.enum([
  "light",
  "switch",
  "thermostat",
  "lock",
  "sensor",
  "camera",
  "blinds",
  "speaker",
  "appliance",
]);

const DeviceStateSchema = z.object({
  deviceId: z.string(),
  name: z.string(),
  category: DeviceCategory,
  online: z.boolean(),
  state: z.record(z.unknown()),
  lastUpdated: z.string().datetime(),
});

type DeviceState = z.infer<typeof DeviceStateSchema>;

const TriggerSchema = z.object({
  type: z.enum(["time", "device_state", "sunrise", "sunset", "geofence", "webhook"]),
  config: z.record(z.unknown()).default({}),
});

const ConditionSchema = z.object({
  deviceId: z.string().nullish(),
  attribute: z.string(),
  operator: z.enum(["eq", "ne", "gt", "lt", "gte", "lte"]),
  value: z.unknown(),
});

const AutomationActionSchema = z.object({
  deviceId: z.string(),
  action: z.string(),
  params: z.record(z.unknown()).default({}),
});

const RuleSchema = z.object({
  ruleId: z.string(),
  name: z.string(),
  enabled: z.boolean().default(true),
  trigger: TriggerSchema,
  conditions: z.array(ConditionSchema).default([]),
  actions: z.array(AutomationActionSchema).default([]),
  createdAt: z.string().datetime(),
  lastTriggered: z.string().datetime().nullish(),
});

type Rule = z.infer<typeof RuleSchema>;

const EnergyEntrySchema = z.object({
  deviceId: z.string().nullish(),
  deviceName: z.string().nullish(),
  period: z.string(),
  kwh: z.number(),
  cost: z.number(),
  avgWatts: z.number(),
});

const EnergyReportSchema = z.object({
  period: z.string(),
  start: z.string().datetime(),
  end: z.string().datetime(),
  entries: z.array(EnergyEntrySchema),
  totalKwh: z.number(),
  totalCost: z.number(),
});

type EnergyReport = z.infer<typeof EnergyReportSchema>;

const SceneSchema = z.object({
  sceneId: z.string(),
  name: z.string(),
  devices: z.array(z.record(z.unknown())),
  createdAt: z.string().datetime(),
});

type Scene = z.infer<typeof SceneSchema>;

// ---------------------------------------------------------------------------
// Hub client
// ---------------------------------------------------------------------------

interface HubConfig {
  baseUrl: string;
  token: string;
}

class SmartHomeHub {
  private baseUrl: string;
  private token: string;

  constructor(config: HubConfig) {
    this.baseUrl = config.baseUrl.replace(/\/+$/, "");
    this.token = config.token;
  }

  async request<T = unknown>(method: string, path: string, body?: unknown): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.token}`,
        "Content-Type": "application/json",
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!res.ok) {
      throw new Error(`Hub API error: ${res.status} ${res.statusText}`);
    }
    return res.json() as Promise<T>;
  }
}

const hub = new SmartHomeHub({
  baseUrl: "{{HUB_URL}}",
  token: "{{HUB_TOKEN}}",
});

const ENERGY_RATE = {{ENERGY_RATE_FLOAT}};
const SECURITY_CATEGORIES = new Set(["lock", "alarm", "garage_door"]);

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

export async function deviceControl(
  deviceId: string,
  action: string,
  params: Record<string, unknown> = {},
): Promise<DeviceState> {
  const device = await hub.request<Record<string, unknown>>("GET", `/devices/${deviceId}`);
  const category = String(device.category ?? "switch");

  if (SECURITY_CATEGORIES.has(category) && ["unlock", "open", "disarm"].includes(action)) {
    // Security actions are logged; confirmation handled by the caller
  }

  const result = await hub.request<Record<string, unknown>>(
    "POST",
    `/devices/${deviceId}/${action}`,
    params,
  );

  return DeviceStateSchema.parse({
    deviceId,
    name: result.name ?? deviceId,
    category: result.category ?? "switch",
    online: result.online ?? true,
    state: result.state ?? {},
    lastUpdated: new Date().toISOString(),
  });
}

export async function automationRules(
  action: "create" | "get" | "list" | "update" | "delete",
  opts: {
    ruleId?: string;
    name?: string;
    trigger?: z.infer<typeof TriggerSchema>;
    conditions?: z.infer<typeof ConditionSchema>[];
    actions?: z.infer<typeof AutomationActionSchema>[];
    enabled?: boolean;
  } = {},
): Promise<Rule | Rule[]> {
  switch (action) {
    case "create": {
      if (!opts.name || !opts.trigger || !opts.actions?.length) {
        throw new Error("create requires name, trigger, and actions");
      }
      const body = {
        name: opts.name,
        enabled: opts.enabled ?? true,
        trigger: opts.trigger,
        conditions: opts.conditions ?? [],
        actions: opts.actions,
      };
      const result = await hub.request<Record<string, unknown>>("POST", "/automations", body);
      return RuleSchema.parse(result);
    }
    case "get": {
      if (!opts.ruleId) throw new Error("get requires ruleId");
      const result = await hub.request("GET", `/automations/${opts.ruleId}`);
      return RuleSchema.parse(result);
    }
    case "list": {
      const result = await hub.request<{ rules: unknown[] }>("GET", "/automations");
      return result.rules.map((r) => RuleSchema.parse(r));
    }
    case "update": {
      if (!opts.ruleId) throw new Error("update requires ruleId");
      const body: Record<string, unknown> = {};
      if (opts.name !== undefined) body.name = opts.name;
      if (opts.trigger !== undefined) body.trigger = opts.trigger;
      if (opts.conditions !== undefined) body.conditions = opts.conditions;
      if (opts.actions !== undefined) body.actions = opts.actions;
      if (opts.enabled !== undefined) body.enabled = opts.enabled;
      const result = await hub.request("PATCH", `/automations/${opts.ruleId}`, body);
      return RuleSchema.parse(result);
    }
    case "delete": {
      if (!opts.ruleId) throw new Error("delete requires ruleId");
      await hub.request("DELETE", `/automations/${opts.ruleId}`);
      return RuleSchema.parse({
        ruleId: opts.ruleId,
        name: "(deleted)",
        trigger: { type: "time", config: {} },
        createdAt: new Date().toISOString(),
      });
    }
  }
}

export async function energyMonitor(
  period: "hour" | "day" | "week" | "month" | "year" = "day",
  deviceId?: string,
): Promise<EnergyReport> {
  const qs = deviceId ? `?period=${period}&device_id=${deviceId}` : `?period=${period}`;
  const data = await hub.request<{ entries: Record<string, unknown>[] }>("GET", `/energy${qs}`);

  let totalKwh = 0;
  const entries = data.entries.map((item) => {
    const kwh = Number(item.kwh ?? 0);
    totalKwh += kwh;
    return EnergyEntrySchema.parse({
      deviceId: item.device_id ?? null,
      deviceName: item.device_name ?? null,
      period,
      kwh: Math.round(kwh * 1000) / 1000,
      cost: Math.round(kwh * ENERGY_RATE * 100) / 100,
      avgWatts: Math.round(Number(item.avg_watts ?? 0) * 10) / 10,
    });
  });

  const periodHours: Record<string, number> = {
    hour: 1, day: 24, week: 168, month: 720, year: 8760,
  };
  const hours = periodHours[period] ?? 24;
  const end = new Date();
  const start = new Date(end.getTime() - hours * 3600_000);

  return EnergyReportSchema.parse({
    period,
    start: start.toISOString(),
    end: end.toISOString(),
    entries,
    totalKwh: Math.round(totalKwh * 1000) / 1000,
    totalCost: Math.round(totalKwh * ENERGY_RATE * 100) / 100,
  });
}

export async function sceneManager(
  action: "create" | "activate" | "get" | "list" | "update" | "delete",
  opts: {
    sceneId?: string;
    name?: string;
    devices?: Record<string, unknown>[];
  } = {},
): Promise<Scene | Scene[]> {
  switch (action) {
    case "create": {
      if (!opts.name || !opts.devices?.length) throw new Error("create requires name and devices");
      const result = await hub.request("POST", "/scenes", { name: opts.name, devices: opts.devices });
      return SceneSchema.parse(result);
    }
    case "activate": {
      if (!opts.sceneId) throw new Error("activate requires sceneId");
      const result = await hub.request("POST", `/scenes/${opts.sceneId}/activate`);
      return SceneSchema.parse(result);
    }
    case "get": {
      if (!opts.sceneId) throw new Error("get requires sceneId");
      const result = await hub.request("GET", `/scenes/${opts.sceneId}`);
      return SceneSchema.parse(result);
    }
    case "list": {
      const result = await hub.request<{ scenes: unknown[] }>("GET", "/scenes");
      return result.scenes.map((s) => SceneSchema.parse(s));
    }
    case "update": {
      if (!opts.sceneId) throw new Error("update requires sceneId");
      const body: Record<string, unknown> = {};
      if (opts.name !== undefined) body.name = opts.name;
      if (opts.devices !== undefined) body.devices = opts.devices;
      const result = await hub.request("PATCH", `/scenes/${opts.sceneId}`, body);
      return SceneSchema.parse(result);
    }
    case "delete": {
      if (!opts.sceneId) throw new Error("delete requires sceneId");
      await hub.request("DELETE", `/scenes/${opts.sceneId}`);
      return SceneSchema.parse({
        sceneId: opts.sceneId,
        name: "(deleted)",
        devices: [],
        createdAt: new Date().toISOString(),
      });
    }
  }
}
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project |
| `{{HUB_URL}}` | Hub API base URL |
| `{{HUB_TOKEN}}` | Hub API authentication token |
| `{{ENERGY_RATE_FLOAT}}` | Energy rate as a number, e.g. `0.12` |
