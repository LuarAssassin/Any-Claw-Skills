# Domain Knowledge: Social Media

Reference knowledge for social media agents covering platform APIs, engagement metrics, content strategy, and scheduling best practices.

## Platform API Overview

| Platform | API Style | Auth Method | Rate Limits (reads) | Rate Limits (writes) |
|---|---|---|---|---|
| Twitter/X | REST + Streaming | OAuth 2.0 Bearer | 300 req/15 min (app) | 200 tweets/15 min |
| LinkedIn | REST | OAuth 2.0 | 100 req/day (search) | 150 shares/day |
| Instagram | Graph API (Meta) | OAuth 2.0 | 200 req/hour | 25 posts/day |
| Mastodon | REST | OAuth 2.0 Bearer | Instance-dependent | 300 statuses/3 hr |
| Bluesky | AT Protocol | App password / OAuth | 3000 req/5 min | 1500 actions/hr |

## Engagement Metrics

### Key Metrics by Platform

- **Engagement Rate**: (likes + comments + shares) / impressions. Healthy range: 1-5% organic.
- **Click-Through Rate (CTR)**: clicks / impressions. Industry average: 0.5-1.5%.
- **Share Rate**: shares / impressions. Indicates content virality.
- **Save Rate**: saves or bookmarks / impressions. Signals long-term value.
- **Reply Rate**: replies / impressions. Measures conversation quality.

### Platform-Specific Signals

- **Twitter/X**: Retweets carry more weight than likes for reach. Quote tweets signal deeper engagement.
- **LinkedIn**: Comments from decision-makers outweigh raw engagement counts. Dwell time matters.
- **Instagram**: Saves and shares outperform likes in algorithm weight. Reels get 2-3x the reach of static posts.
- **Mastodon**: Boosts (shares) are the primary distribution mechanism. No algorithmic amplification.

## Content Strategy

### Content Pillars Framework

Organize content around 3-5 recurring themes (pillars) that align with brand goals:
1. **Educational**: How-tos, tutorials, industry insights.
2. **Community**: User stories, polls, Q&A threads.
3. **Promotional**: Product launches, offers, case studies.
4. **Behind-the-scenes**: Team culture, process, development updates.
5. **Curated**: Third-party content with added commentary.

### Platform-Specific Formatting

| Platform | Max Length | Best Media | Hashtag Strategy |
|---|---|---|---|
| Twitter/X | 280 chars (4000 for Premium) | Images, short video | 1-2 targeted hashtags |
| LinkedIn | 3000 chars | Carousels (PDF), native video | 3-5 industry hashtags |
| Instagram | 2200 chars caption | Reels, carousels | 5-10 mixed (broad + niche) |
| Mastodon | 500 chars (instance-dependent) | Images, alt text required | Hashtags are primary discovery |
| Bluesky | 300 chars | Images, link cards | Limited hashtag adoption |

### Content Quality Signals

- **Relevance**: Does it match the audience's current interests?
- **Timeliness**: Is it tied to a trending topic or seasonal event?
- **Originality**: Does it add a unique perspective or data?
- **Actionability**: Does it give the reader something to do next?
- **Shareability**: Would someone share this to look informed or helpful?

## Scheduling Best Practices

### Optimal Posting Windows (UTC)

| Platform | Weekday Peak | Weekend Peak | Frequency |
|---|---|---|---|
| Twitter/X | 13:00-15:00 | 11:00-13:00 | 3-5 per day |
| LinkedIn | 07:00-09:00, 17:00-18:00 | Low engagement | 1-2 per day |
| Instagram | 11:00-14:00, 19:00-21:00 | 10:00-14:00 | 1-2 per day |
| Mastodon | 14:00-17:00 | 12:00-15:00 | 2-4 per day |

### Scheduling Rules

- Always convert to the audience's primary timezone before scheduling.
- Space posts at least 2 hours apart on the same platform.
- Avoid scheduling during major holidays unless content is holiday-relevant.
- Queue evergreen content for low-engagement windows to maintain presence.
- Monitor scheduled posts for conflicts with breaking news or sensitive events.

### Cross-Platform Coordination

- Stagger cross-posts by 30-60 minutes; avoid identical simultaneous posts.
- Adapt content format per platform rather than copying verbatim.
- Use platform-native features (Twitter threads, LinkedIn polls, Instagram Stories) instead of link-only posts.
- Track which platform drives the most conversions, not just engagement.

## Brand Safety

### Content Review Checklist

Before publishing or recommending content, verify:
1. No references to competitors in a negative context.
2. No unverified claims or statistics without sources.
3. No engagement bait (e.g., "Like if you agree").
4. No content from accounts associated with controversy.
5. Compliant with platform terms of service.
6. Accessible: images have alt text, videos have captions.

### Risk Categories

- **High risk**: Political topics, health claims, financial advice.
- **Medium risk**: Trending memes (may age poorly), user-generated content (verify source).
- **Low risk**: Industry news, educational content, product updates.
