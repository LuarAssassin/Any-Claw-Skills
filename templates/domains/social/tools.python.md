# Social Media Tools (Python)

Python tool implementations for social media monitoring, curation, trend analysis, and post scheduling.

## Dependencies

```
httpx>=0.27.0
pydantic>=2.0.0
```

## Generated File: `tools/social_tools.py`

```python
"""Social media tools for {{PROJECT_NAME}}.

Provides feed monitoring, content curation, trend analysis, and post
scheduling across supported platforms.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
from datetime import datetime, timezone
from enum import Enum
from typing import Any

import httpx
from pydantic import BaseModel, Field

logger = logging.getLogger("{{PACKAGE_NAME}}.social")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PLATFORM_ENDPOINTS: dict[str, str] = {
    "twitter": "{{TWITTER_API_BASE}}",
    "linkedin": "{{LINKEDIN_API_BASE}}",
    "instagram": "{{INSTAGRAM_API_BASE}}",
    "mastodon": "{{MASTODON_API_BASE}}",
}

API_KEYS: dict[str, str] = {
    "twitter": "{{TWITTER_API_KEY}}",
    "linkedin": "{{LINKEDIN_API_KEY}}",
    "instagram": "{{INSTAGRAM_API_KEY}}",
    "mastodon": "{{MASTODON_API_KEY}}",
}


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class Platform(str, Enum):
    TWITTER = "twitter"
    LINKEDIN = "linkedin"
    INSTAGRAM = "instagram"
    MASTODON = "mastodon"


class FeedItem(BaseModel):
    """A single post or update from a social feed."""
    post_id: str
    platform: str
    author: str
    author_handle: str
    content: str
    url: str
    published_at: datetime
    likes: int = 0
    shares: int = 0
    comments: int = 0
    matched_keywords: list[str] = Field(default_factory=list)
    media_urls: list[str] = Field(default_factory=list)


class FeedResults(BaseModel):
    """Results from monitoring social feeds."""
    platform: str
    keywords: list[str]
    items: list[FeedItem]
    total_matches: int
    query_time_ms: float
    next_cursor: str | None = None


class CuratedItem(BaseModel):
    """A piece of curated content with relevance scoring."""
    source_platform: str
    source_author: str
    title: str
    summary: str
    url: str
    relevance_score: float = Field(ge=0.0, le=1.0)
    engagement_rate: float = 0.0
    suggested_action: str = "share"
    tags: list[str] = Field(default_factory=list)


class CuratedContent(BaseModel):
    """Collection of curated content on a topic."""
    topic: str
    items: list[CuratedItem]
    total_candidates: int
    curated_at: datetime


class TrendEntry(BaseModel):
    """A single trending topic or hashtag."""
    name: str
    hashtag: str | None = None
    category: str
    volume: int
    velocity: str  # "rising", "peaking", "declining"
    relevance: str  # "high", "medium", "low"
    sample_posts: list[str] = Field(default_factory=list)


class TrendReport(BaseModel):
    """Report of trending topics for a platform."""
    platform: str
    category: str
    trends: list[TrendEntry]
    generated_at: datetime
    period_hours: int = 24


class ScheduleResult(BaseModel):
    """Result of scheduling a post."""
    success: bool
    post_id: str | None = None
    platform: str
    scheduled_time: datetime
    content_preview: str
    error: str | None = None


# ---------------------------------------------------------------------------
# HTTP client
# ---------------------------------------------------------------------------

async def _get_client() -> httpx.AsyncClient:
    """Return a shared async HTTP client."""
    return httpx.AsyncClient(
        timeout=httpx.Timeout(30.0, connect=10.0),
        headers={"User-Agent": "{{PROJECT_NAME}}/1.0"},
    )


def _platform_headers(platform: str) -> dict[str, str]:
    """Build auth headers for a platform API."""
    key = API_KEYS.get(platform, "")
    return {"Authorization": f"Bearer {key}"}


# ---------------------------------------------------------------------------
# Tool: feed_monitor
# ---------------------------------------------------------------------------

async def feed_monitor(platform: str, keywords: list[str]) -> FeedResults:
    """Monitor a social feed for posts matching the given keywords.

    Args:
        platform: Target platform (twitter, linkedin, instagram, mastodon).
        keywords: List of keywords or hashtags to track.

    Returns:
        FeedResults with matching posts.
    """
    start = asyncio.get_event_loop().time()
    base_url = PLATFORM_ENDPOINTS.get(platform)
    if not base_url:
        raise ValueError(f"Unsupported platform: {platform}")

    items: list[FeedItem] = []
    async with await _get_client() as client:
        for keyword in keywords:
            resp = await client.get(
                f"{base_url}/search/posts",
                params={"q": keyword, "limit": 25},
                headers=_platform_headers(platform),
            )
            resp.raise_for_status()
            data = resp.json()

            for post in data.get("results", []):
                item = FeedItem(
                    post_id=post["id"],
                    platform=platform,
                    author=post.get("author_name", ""),
                    author_handle=post.get("author_handle", ""),
                    content=post.get("text", ""),
                    url=post.get("url", ""),
                    published_at=datetime.fromisoformat(post["created_at"]),
                    likes=post.get("likes", 0),
                    shares=post.get("shares", 0),
                    comments=post.get("comments", 0),
                    matched_keywords=[keyword],
                    media_urls=post.get("media_urls", []),
                )
                items.append(item)

    # Deduplicate by post_id
    seen: set[str] = set()
    unique: list[FeedItem] = []
    for item in items:
        if item.post_id not in seen:
            seen.add(item.post_id)
            unique.append(item)

    elapsed = (asyncio.get_event_loop().time() - start) * 1000
    logger.info("feed_monitor: %s matched %d posts in %.0fms", platform, len(unique), elapsed)

    return FeedResults(
        platform=platform,
        keywords=keywords,
        items=unique,
        total_matches=len(unique),
        query_time_ms=round(elapsed, 1),
    )


# ---------------------------------------------------------------------------
# Tool: content_curator
# ---------------------------------------------------------------------------

async def content_curator(topic: str, count: int = 10) -> CuratedContent:
    """Curate top content on a given topic across platforms.

    Args:
        topic: The topic or theme to curate content for.
        count: Maximum number of items to return.

    Returns:
        CuratedContent with scored and ranked items.
    """
    all_items: list[CuratedItem] = []

    async with await _get_client() as client:
        for platform, base_url in PLATFORM_ENDPOINTS.items():
            try:
                resp = await client.get(
                    f"{base_url}/search/posts",
                    params={"q": topic, "limit": count * 2, "sort": "engagement"},
                    headers=_platform_headers(platform),
                )
                resp.raise_for_status()
                data = resp.json()

                for post in data.get("results", []):
                    engagement = post.get("likes", 0) + post.get("shares", 0) * 2
                    max_engagement = max(engagement, 1)
                    score = min(engagement / max_engagement, 1.0)

                    item = CuratedItem(
                        source_platform=platform,
                        source_author=post.get("author_name", "unknown"),
                        title=post.get("title", post.get("text", "")[:80]),
                        summary=post.get("text", "")[:280],
                        url=post.get("url", ""),
                        relevance_score=round(score, 3),
                        engagement_rate=post.get("engagement_rate", 0.0),
                        suggested_action=_suggest_action(score),
                        tags=post.get("tags", []),
                    )
                    all_items.append(item)
            except httpx.HTTPError as exc:
                logger.warning("content_curator: %s failed: %s", platform, exc)

    # Sort by relevance and trim
    all_items.sort(key=lambda x: x.relevance_score, reverse=True)
    curated = all_items[:count]

    return CuratedContent(
        topic=topic,
        items=curated,
        total_candidates=len(all_items),
        curated_at=datetime.now(timezone.utc),
    )


def _suggest_action(score: float) -> str:
    """Map a relevance score to a suggested action."""
    if score >= 0.8:
        return "share"
    if score >= 0.5:
        return "engage"
    if score >= 0.3:
        return "save"
    return "skip"


# ---------------------------------------------------------------------------
# Tool: trend_analyzer
# ---------------------------------------------------------------------------

async def trend_analyzer(platform: str, category: str = "general") -> TrendReport:
    """Analyze trending topics on a platform within a category.

    Args:
        platform: Target platform to analyze.
        category: Topic category to filter trends (e.g. "tech", "general").

    Returns:
        TrendReport with ranked trending topics.
    """
    base_url = PLATFORM_ENDPOINTS.get(platform)
    if not base_url:
        raise ValueError(f"Unsupported platform: {platform}")

    trends: list[TrendEntry] = []
    async with await _get_client() as client:
        resp = await client.get(
            f"{base_url}/trends",
            params={"category": category, "limit": 20},
            headers=_platform_headers(platform),
        )
        resp.raise_for_status()
        data = resp.json()

        for t in data.get("trends", []):
            volume = t.get("volume", 0)
            prev_volume = t.get("previous_volume", volume)
            velocity = _compute_velocity(volume, prev_volume)

            entry = TrendEntry(
                name=t.get("name", ""),
                hashtag=t.get("hashtag"),
                category=category,
                volume=volume,
                velocity=velocity,
                relevance=t.get("relevance", "medium"),
                sample_posts=t.get("sample_posts", [])[:3],
            )
            trends.append(entry)

    trends.sort(key=lambda x: x.volume, reverse=True)
    logger.info("trend_analyzer: %s/%s found %d trends", platform, category, len(trends))

    return TrendReport(
        platform=platform,
        category=category,
        trends=trends,
        generated_at=datetime.now(timezone.utc),
    )


def _compute_velocity(current: int, previous: int) -> str:
    """Determine trend velocity from volume comparison."""
    if previous == 0:
        return "rising"
    ratio = current / previous
    if ratio > 1.5:
        return "rising"
    if ratio > 0.8:
        return "peaking"
    return "declining"


# ---------------------------------------------------------------------------
# Tool: post_scheduler
# ---------------------------------------------------------------------------

async def post_scheduler(
    platform: str,
    content: str,
    schedule_time: str,
) -> ScheduleResult:
    """Schedule a post for publication on a platform.

    Args:
        platform: Target platform to post on.
        content: The post content (text, may include hashtags).
        schedule_time: ISO-8601 datetime for when to publish.

    Returns:
        ScheduleResult indicating success or failure.
    """
    base_url = PLATFORM_ENDPOINTS.get(platform)
    if not base_url:
        return ScheduleResult(
            success=False,
            platform=platform,
            scheduled_time=datetime.fromisoformat(schedule_time),
            content_preview=content[:100],
            error=f"Unsupported platform: {platform}",
        )

    scheduled_dt = datetime.fromisoformat(schedule_time)
    if scheduled_dt < datetime.now(timezone.utc):
        return ScheduleResult(
            success=False,
            platform=platform,
            scheduled_time=scheduled_dt,
            content_preview=content[:100],
            error="Scheduled time is in the past",
        )

    async with await _get_client() as client:
        try:
            resp = await client.post(
                f"{base_url}/posts/schedule",
                json={
                    "content": content,
                    "scheduled_at": schedule_time,
                },
                headers=_platform_headers(platform),
            )
            resp.raise_for_status()
            data = resp.json()

            post_id = data.get("id", hashlib.sha256(content.encode()).hexdigest()[:12])
            logger.info("post_scheduler: scheduled %s on %s at %s", post_id, platform, schedule_time)

            return ScheduleResult(
                success=True,
                post_id=post_id,
                platform=platform,
                scheduled_time=scheduled_dt,
                content_preview=content[:100],
            )
        except httpx.HTTPError as exc:
            return ScheduleResult(
                success=False,
                platform=platform,
                scheduled_time=scheduled_dt,
                content_preview=content[:100],
                error=str(exc),
            )
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Project name for user-agent and logging |
| `{{PACKAGE_NAME}}` | Python package name for logger namespace |
| `{{TWITTER_API_BASE}}` | Twitter/X API base URL |
| `{{TWITTER_API_KEY}}` | Twitter/X bearer token |
| `{{LINKEDIN_API_BASE}}` | LinkedIn API base URL |
| `{{LINKEDIN_API_KEY}}` | LinkedIn access token |
| `{{INSTAGRAM_API_BASE}}` | Instagram Graph API base URL |
| `{{INSTAGRAM_API_KEY}}` | Instagram access token |
| `{{MASTODON_API_BASE}}` | Mastodon instance API base URL |
| `{{MASTODON_API_KEY}}` | Mastodon access token |
