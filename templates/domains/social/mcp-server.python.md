# MCP Server: Social Media (Python)

FastMCP server exposing social media tools as MCP resources and tools.

## Dependencies

```
fastmcp>=2.0.0
httpx>=0.27.0
pydantic>=2.0.0
```

## Generated File: `server/social_mcp.py`

```python
"""MCP server for {{PROJECT_NAME}} social media tools.

Exposes feed monitoring, content curation, trend analysis, and post
scheduling as MCP tools via the FastMCP framework.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Annotated

from fastmcp import FastMCP
from pydantic import BaseModel, Field

from {{PACKAGE_NAME}}.tools.social_tools import (
    content_curator,
    feed_monitor,
    post_scheduler,
    trend_analyzer,
)

logger = logging.getLogger("{{PACKAGE_NAME}}.mcp")

# ---------------------------------------------------------------------------
# Server setup
# ---------------------------------------------------------------------------

mcp = FastMCP(
    "{{PROJECT_NAME}} Social Media",
    description="Social media monitoring, curation, trend analysis, and scheduling tools.",
)


# ---------------------------------------------------------------------------
# Input models
# ---------------------------------------------------------------------------

class FeedMonitorInput(BaseModel):
    platform: Annotated[str, Field(description="Target platform: twitter, linkedin, instagram, mastodon")]
    keywords: Annotated[list[str], Field(description="Keywords or hashtags to monitor")]


class ContentCuratorInput(BaseModel):
    topic: Annotated[str, Field(description="Topic or theme to curate content for")]
    count: Annotated[int, Field(default=10, ge=1, le=50, description="Max items to return")]


class TrendAnalyzerInput(BaseModel):
    platform: Annotated[str, Field(description="Platform to analyze trends on")]
    category: Annotated[str, Field(default="general", description="Topic category filter")]


class PostSchedulerInput(BaseModel):
    platform: Annotated[str, Field(description="Platform to schedule the post on")]
    content: Annotated[str, Field(description="Post content text")]
    schedule_time: Annotated[str, Field(description="ISO-8601 datetime for publication")]


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

@mcp.tool()
async def monitor_feed(input: FeedMonitorInput) -> dict:
    """Monitor a social media feed for posts matching specified keywords.

    Searches the target platform for recent posts containing any of the
    provided keywords. Returns matched posts with engagement metrics.
    """
    logger.info("monitor_feed: platform=%s keywords=%s", input.platform, input.keywords)
    result = await feed_monitor(input.platform, input.keywords)
    return result.model_dump(mode="json")


@mcp.tool()
async def curate_content(input: ContentCuratorInput) -> dict:
    """Curate top content on a given topic across all configured platforms.

    Searches multiple platforms, scores posts by relevance and engagement,
    and returns the best content with suggested actions (share, engage, save, skip).
    """
    logger.info("curate_content: topic=%s count=%d", input.topic, input.count)
    result = await content_curator(input.topic, input.count)
    return result.model_dump(mode="json")


@mcp.tool()
async def analyze_trends(input: TrendAnalyzerInput) -> dict:
    """Analyze trending topics on a platform within a category.

    Returns trending topics ranked by volume with velocity indicators
    (rising, peaking, declining) and relevance scoring.
    """
    logger.info("analyze_trends: platform=%s category=%s", input.platform, input.category)
    result = await trend_analyzer(input.platform, input.category)
    return result.model_dump(mode="json")


@mcp.tool()
async def schedule_post(input: PostSchedulerInput) -> dict:
    """Schedule a post for future publication on a platform.

    Validates the scheduled time, submits the post to the platform API,
    and returns a confirmation with the scheduled post ID.
    """
    logger.info("schedule_post: platform=%s time=%s", input.platform, input.schedule_time)
    result = await post_scheduler(input.platform, input.content, input.schedule_time)
    return result.model_dump(mode="json")


# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

@mcp.resource("social://platforms")
async def list_platforms() -> dict:
    """List all supported social media platforms and their status."""
    from {{PACKAGE_NAME}}.tools.social_tools import PLATFORM_ENDPOINTS
    return {
        "platforms": [
            {"name": name, "configured": bool(url and not url.startswith("{"))}
            for name, url in PLATFORM_ENDPOINTS.items()
        ],
        "queried_at": datetime.now(timezone.utc).isoformat(),
    }


@mcp.resource("social://trends/{platform}")
async def get_trends(platform: str) -> dict:
    """Get current trending topics for a platform."""
    result = await trend_analyzer(platform, "general")
    return result.model_dump(mode="json")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    """Run the MCP server."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    logger.info("Starting {{PROJECT_NAME}} Social MCP server")
    mcp.run()


if __name__ == "__main__":
    main()
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Project name used in server metadata and logging |
| `{{PACKAGE_NAME}}` | Python package name for imports (e.g. `my_agent`) |
