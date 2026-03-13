# Social Media Tools (TypeScript)

TypeScript tool implementations for social media monitoring, curation, trend analysis, and post scheduling.

## Dependencies

```bash
npm install zod
```

## Generated File: `tools/socialTools.ts`

```typescript
/**
 * Social media tools for {{PROJECT_NAME}}.
 *
 * Provides feed monitoring, content curation, trend analysis, and post
 * scheduling across supported platforms.
 */

import { z } from "zod";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const PLATFORM_ENDPOINTS: Record<string, string> = {
  twitter: "{{TWITTER_API_BASE}}",
  linkedin: "{{LINKEDIN_API_BASE}}",
  instagram: "{{INSTAGRAM_API_BASE}}",
  mastodon: "{{MASTODON_API_BASE}}",
};

const API_KEYS: Record<string, string> = {
  twitter: "{{TWITTER_API_KEY}}",
  linkedin: "{{LINKEDIN_API_KEY}}",
  instagram: "{{INSTAGRAM_API_KEY}}",
  mastodon: "{{MASTODON_API_KEY}}",
};

// ---------------------------------------------------------------------------
// Schemas and types
// ---------------------------------------------------------------------------

export const FeedItemSchema = z.object({
  postId: z.string(),
  platform: z.string(),
  author: z.string(),
  authorHandle: z.string(),
  content: z.string(),
  url: z.string(),
  publishedAt: z.string().datetime(),
  likes: z.number().default(0),
  shares: z.number().default(0),
  comments: z.number().default(0),
  matchedKeywords: z.array(z.string()).default([]),
  mediaUrls: z.array(z.string()).default([]),
});
export type FeedItem = z.infer<typeof FeedItemSchema>;

export interface FeedResults {
  platform: string;
  keywords: string[];
  items: FeedItem[];
  totalMatches: number;
  queryTimeMs: number;
  nextCursor: string | null;
}

export interface CuratedItem {
  sourcePlatform: string;
  sourceAuthor: string;
  title: string;
  summary: string;
  url: string;
  relevanceScore: number;
  engagementRate: number;
  suggestedAction: string;
  tags: string[];
}

export interface CuratedContent {
  topic: string;
  items: CuratedItem[];
  totalCandidates: number;
  curatedAt: string;
}

export interface TrendEntry {
  name: string;
  hashtag: string | null;
  category: string;
  volume: number;
  velocity: "rising" | "peaking" | "declining";
  relevance: "high" | "medium" | "low";
  samplePosts: string[];
}

export interface TrendReport {
  platform: string;
  category: string;
  trends: TrendEntry[];
  generatedAt: string;
  periodHours: number;
}

export interface ScheduleResult {
  success: boolean;
  postId: string | null;
  platform: string;
  scheduledTime: string;
  contentPreview: string;
  error: string | null;
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

function platformHeaders(platform: string): Record<string, string> {
  const key = API_KEYS[platform] ?? "";
  return {
    Authorization: `Bearer ${key}`,
    "Content-Type": "application/json",
    "User-Agent": "{{PROJECT_NAME}}/1.0",
  };
}

async function apiGet(platform: string, path: string, params: Record<string, string>): Promise<unknown> {
  const base = PLATFORM_ENDPOINTS[platform];
  if (!base) throw new Error(`Unsupported platform: ${platform}`);
  const url = new URL(path, base);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  const resp = await fetch(url.toString(), { headers: platformHeaders(platform) });
  if (!resp.ok) throw new Error(`API error ${resp.status}: ${resp.statusText}`);
  return resp.json();
}

async function apiPost(platform: string, path: string, body: unknown): Promise<unknown> {
  const base = PLATFORM_ENDPOINTS[platform];
  if (!base) throw new Error(`Unsupported platform: ${platform}`);
  const url = new URL(path, base);
  const resp = await fetch(url.toString(), {
    method: "POST",
    headers: platformHeaders(platform),
    body: JSON.stringify(body),
  });
  if (!resp.ok) throw new Error(`API error ${resp.status}: ${resp.statusText}`);
  return resp.json();
}

// ---------------------------------------------------------------------------
// Tool: feedMonitor
// ---------------------------------------------------------------------------

export async function feedMonitor(platform: string, keywords: string[]): Promise<FeedResults> {
  const start = performance.now();
  const items: FeedItem[] = [];

  for (const keyword of keywords) {
    const data = (await apiGet(platform, "/search/posts", { q: keyword, limit: "25" })) as {
      results?: Array<Record<string, unknown>>;
    };
    for (const post of data.results ?? []) {
      items.push({
        postId: String(post.id ?? ""),
        platform,
        author: String(post.author_name ?? ""),
        authorHandle: String(post.author_handle ?? ""),
        content: String(post.text ?? ""),
        url: String(post.url ?? ""),
        publishedAt: String(post.created_at ?? new Date().toISOString()),
        likes: Number(post.likes ?? 0),
        shares: Number(post.shares ?? 0),
        comments: Number(post.comments ?? 0),
        matchedKeywords: [keyword],
        mediaUrls: (post.media_urls as string[]) ?? [],
      });
    }
  }

  // Deduplicate by postId
  const seen = new Set<string>();
  const unique = items.filter((item) => {
    if (seen.has(item.postId)) return false;
    seen.add(item.postId);
    return true;
  });

  const elapsed = performance.now() - start;
  return {
    platform,
    keywords,
    items: unique,
    totalMatches: unique.length,
    queryTimeMs: Math.round(elapsed * 10) / 10,
    nextCursor: null,
  };
}

// ---------------------------------------------------------------------------
// Tool: contentCurator
// ---------------------------------------------------------------------------

function suggestAction(score: number): string {
  if (score >= 0.8) return "share";
  if (score >= 0.5) return "engage";
  if (score >= 0.3) return "save";
  return "skip";
}

export async function contentCurator(topic: string, count: number = 10): Promise<CuratedContent> {
  const allItems: CuratedItem[] = [];

  for (const [platform, baseUrl] of Object.entries(PLATFORM_ENDPOINTS)) {
    try {
      const data = (await apiGet(platform, "/search/posts", {
        q: topic,
        limit: String(count * 2),
        sort: "engagement",
      })) as { results?: Array<Record<string, unknown>> };

      for (const post of data.results ?? []) {
        const engagement = Number(post.likes ?? 0) + Number(post.shares ?? 0) * 2;
        const maxEngagement = Math.max(engagement, 1);
        const score = Math.min(engagement / maxEngagement, 1.0);

        allItems.push({
          sourcePlatform: platform,
          sourceAuthor: String(post.author_name ?? "unknown"),
          title: String(post.title ?? String(post.text ?? "").slice(0, 80)),
          summary: String(post.text ?? "").slice(0, 280),
          url: String(post.url ?? ""),
          relevanceScore: Math.round(score * 1000) / 1000,
          engagementRate: Number(post.engagement_rate ?? 0),
          suggestedAction: suggestAction(score),
          tags: (post.tags as string[]) ?? [],
        });
      }
    } catch (err) {
      console.warn(`contentCurator: ${platform} failed:`, err);
    }
  }

  allItems.sort((a, b) => b.relevanceScore - a.relevanceScore);

  return {
    topic,
    items: allItems.slice(0, count),
    totalCandidates: allItems.length,
    curatedAt: new Date().toISOString(),
  };
}

// ---------------------------------------------------------------------------
// Tool: trendAnalyzer
// ---------------------------------------------------------------------------

function computeVelocity(current: number, previous: number): "rising" | "peaking" | "declining" {
  if (previous === 0) return "rising";
  const ratio = current / previous;
  if (ratio > 1.5) return "rising";
  if (ratio > 0.8) return "peaking";
  return "declining";
}

export async function trendAnalyzer(platform: string, category: string = "general"): Promise<TrendReport> {
  const data = (await apiGet(platform, "/trends", { category, limit: "20" })) as {
    trends?: Array<Record<string, unknown>>;
  };

  const trends: TrendEntry[] = (data.trends ?? []).map((t) => {
    const volume = Number(t.volume ?? 0);
    const prevVolume = Number(t.previous_volume ?? volume);
    return {
      name: String(t.name ?? ""),
      hashtag: t.hashtag ? String(t.hashtag) : null,
      category,
      volume,
      velocity: computeVelocity(volume, prevVolume),
      relevance: (t.relevance as "high" | "medium" | "low") ?? "medium",
      samplePosts: ((t.sample_posts as string[]) ?? []).slice(0, 3),
    };
  });

  trends.sort((a, b) => b.volume - a.volume);

  return {
    platform,
    category,
    trends,
    generatedAt: new Date().toISOString(),
    periodHours: 24,
  };
}

// ---------------------------------------------------------------------------
// Tool: postScheduler
// ---------------------------------------------------------------------------

export async function postScheduler(
  platform: string,
  content: string,
  scheduleTime: string,
): Promise<ScheduleResult> {
  if (!PLATFORM_ENDPOINTS[platform]) {
    return {
      success: false,
      postId: null,
      platform,
      scheduledTime: scheduleTime,
      contentPreview: content.slice(0, 100),
      error: `Unsupported platform: ${platform}`,
    };
  }

  const scheduledDt = new Date(scheduleTime);
  if (scheduledDt.getTime() < Date.now()) {
    return {
      success: false,
      postId: null,
      platform,
      scheduledTime: scheduleTime,
      contentPreview: content.slice(0, 100),
      error: "Scheduled time is in the past",
    };
  }

  try {
    const data = (await apiPost(platform, "/posts/schedule", {
      content,
      scheduled_at: scheduleTime,
    })) as { id?: string };

    return {
      success: true,
      postId: data.id ?? null,
      platform,
      scheduledTime: scheduleTime,
      contentPreview: content.slice(0, 100),
      error: null,
    };
  } catch (err) {
    return {
      success: false,
      postId: null,
      platform,
      scheduledTime: scheduleTime,
      contentPreview: content.slice(0, 100),
      error: err instanceof Error ? err.message : String(err),
    };
  }
}
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Project name for user-agent header |
| `{{TWITTER_API_BASE}}` | Twitter/X API base URL |
| `{{TWITTER_API_KEY}}` | Twitter/X bearer token |
| `{{LINKEDIN_API_BASE}}` | LinkedIn API base URL |
| `{{LINKEDIN_API_KEY}}` | LinkedIn access token |
| `{{INSTAGRAM_API_BASE}}` | Instagram Graph API base URL |
| `{{INSTAGRAM_API_KEY}}` | Instagram access token |
| `{{MASTODON_API_BASE}}` | Mastodon instance API base URL |
| `{{MASTODON_API_KEY}}` | Mastodon access token |
