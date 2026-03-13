# Social Media Tools (Go)

Go tool implementations for social media monitoring, curation, trend analysis, and post scheduling.

## Dependencies

```
go get github.com/go-resty/resty/v2
```

## Generated File: `tools/social_tools.go`

```go
// Package tools provides social media tools for {{PROJECT_NAME}}.
//
// Implements feed monitoring, content curation, trend analysis, and post
// scheduling across supported platforms.
package tools

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"
)

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

var platformEndpoints = map[string]string{
	"twitter":   "{{TWITTER_API_BASE}}",
	"linkedin":  "{{LINKEDIN_API_BASE}}",
	"instagram": "{{INSTAGRAM_API_BASE}}",
	"mastodon":  "{{MASTODON_API_BASE}}",
}

var apiKeys = map[string]string{
	"twitter":   "{{TWITTER_API_KEY}}",
	"linkedin":  "{{LINKEDIN_API_KEY}}",
	"instagram": "{{INSTAGRAM_API_KEY}}",
	"mastodon":  "{{MASTODON_API_KEY}}",
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

// FeedItem represents a single post from a social feed.
type FeedItem struct {
	PostID          string    `json:"post_id"`
	Platform        string    `json:"platform"`
	Author          string    `json:"author"`
	AuthorHandle    string    `json:"author_handle"`
	Content         string    `json:"content"`
	URL             string    `json:"url"`
	PublishedAt     time.Time `json:"published_at"`
	Likes           int       `json:"likes"`
	Shares          int       `json:"shares"`
	Comments        int       `json:"comments"`
	MatchedKeywords []string  `json:"matched_keywords"`
	MediaURLs       []string  `json:"media_urls"`
}

// FeedResults contains the results of a feed monitoring operation.
type FeedResults struct {
	Platform     string     `json:"platform"`
	Keywords     []string   `json:"keywords"`
	Items        []FeedItem `json:"items"`
	TotalMatches int        `json:"total_matches"`
	QueryTimeMs  float64    `json:"query_time_ms"`
	NextCursor   *string    `json:"next_cursor,omitempty"`
}

// CuratedItem represents a single piece of curated content.
type CuratedItem struct {
	SourcePlatform  string   `json:"source_platform"`
	SourceAuthor    string   `json:"source_author"`
	Title           string   `json:"title"`
	Summary         string   `json:"summary"`
	URL             string   `json:"url"`
	RelevanceScore  float64  `json:"relevance_score"`
	EngagementRate  float64  `json:"engagement_rate"`
	SuggestedAction string   `json:"suggested_action"`
	Tags            []string `json:"tags"`
}

// CuratedContent is a collection of curated content on a topic.
type CuratedContent struct {
	Topic           string        `json:"topic"`
	Items           []CuratedItem `json:"items"`
	TotalCandidates int           `json:"total_candidates"`
	CuratedAt       time.Time     `json:"curated_at"`
}

// TrendEntry represents a single trending topic.
type TrendEntry struct {
	Name        string   `json:"name"`
	Hashtag     *string  `json:"hashtag,omitempty"`
	Category    string   `json:"category"`
	Volume      int      `json:"volume"`
	Velocity    string   `json:"velocity"`
	Relevance   string   `json:"relevance"`
	SamplePosts []string `json:"sample_posts"`
}

// TrendReport contains trending topics for a platform.
type TrendReport struct {
	Platform    string       `json:"platform"`
	Category    string       `json:"category"`
	Trends      []TrendEntry `json:"trends"`
	GeneratedAt time.Time    `json:"generated_at"`
	PeriodHours int          `json:"period_hours"`
}

// ScheduleResult is the outcome of scheduling a post.
type ScheduleResult struct {
	Success        bool      `json:"success"`
	PostID         *string   `json:"post_id,omitempty"`
	Platform       string    `json:"platform"`
	ScheduledTime  time.Time `json:"scheduled_time"`
	ContentPreview string    `json:"content_preview"`
	Error          *string   `json:"error,omitempty"`
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

var httpClient = &http.Client{Timeout: 30 * time.Second}

func apiGet(ctx context.Context, platform, path string, params map[string]string) (map[string]interface{}, error) {
	base, ok := platformEndpoints[platform]
	if !ok {
		return nil, fmt.Errorf("unsupported platform: %s", platform)
	}
	u, err := url.Parse(base + path)
	if err != nil {
		return nil, err
	}
	q := u.Query()
	for k, v := range params {
		q.Set(k, v)
	}
	u.RawQuery = q.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+apiKeys[platform])
	req.Header.Set("User-Agent", "{{PROJECT_NAME}}/1.0")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API error: %s", resp.Status)
	}

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	return result, nil
}

func apiPost(ctx context.Context, platform, path string, body interface{}) (map[string]interface{}, error) {
	base, ok := platformEndpoints[platform]
	if !ok {
		return nil, fmt.Errorf("unsupported platform: %s", platform)
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+path, strings.NewReader(string(payload)))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+apiKeys[platform])
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "{{PROJECT_NAME}}/1.0")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return nil, fmt.Errorf("API error: %s", resp.Status)
	}

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	return result, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// ---------------------------------------------------------------------------
// Tool: FeedMonitor
// ---------------------------------------------------------------------------

// FeedMonitor monitors a social feed for posts matching the given keywords.
func FeedMonitor(ctx context.Context, platform string, keywords []string) (*FeedResults, error) {
	start := time.Now()

	if _, ok := platformEndpoints[platform]; !ok {
		return nil, fmt.Errorf("unsupported platform: %s", platform)
	}

	var items []FeedItem
	for _, keyword := range keywords {
		data, err := apiGet(ctx, platform, "/search/posts", map[string]string{
			"q":     keyword,
			"limit": "25",
		})
		if err != nil {
			return nil, fmt.Errorf("feed search for %q: %w", keyword, err)
		}

		results, _ := data["results"].([]interface{})
		for _, r := range results {
			post, _ := r.(map[string]interface{})
			publishedAt, _ := time.Parse(time.RFC3339, fmt.Sprint(post["created_at"]))
			mediaURLs := extractStringSlice(post["media_urls"])

			items = append(items, FeedItem{
				PostID:          fmt.Sprint(post["id"]),
				Platform:        platform,
				Author:          fmt.Sprint(post["author_name"]),
				AuthorHandle:    fmt.Sprint(post["author_handle"]),
				Content:         fmt.Sprint(post["text"]),
				URL:             fmt.Sprint(post["url"]),
				PublishedAt:     publishedAt,
				Likes:           toInt(post["likes"]),
				Shares:          toInt(post["shares"]),
				Comments:        toInt(post["comments"]),
				MatchedKeywords: []string{keyword},
				MediaURLs:       mediaURLs,
			})
		}
	}

	// Deduplicate by PostID
	seen := make(map[string]bool)
	unique := make([]FeedItem, 0, len(items))
	for _, item := range items {
		if !seen[item.PostID] {
			seen[item.PostID] = true
			unique = append(unique, item)
		}
	}

	elapsed := float64(time.Since(start).Microseconds()) / 1000.0
	log.Printf("FeedMonitor: %s matched %d posts in %.0fms", platform, len(unique), elapsed)

	return &FeedResults{
		Platform:     platform,
		Keywords:     keywords,
		Items:        unique,
		TotalMatches: len(unique),
		QueryTimeMs:  math.Round(elapsed*10) / 10,
	}, nil
}

// ---------------------------------------------------------------------------
// Tool: ContentCurator
// ---------------------------------------------------------------------------

func suggestAction(score float64) string {
	if score >= 0.8 {
		return "share"
	}
	if score >= 0.5 {
		return "engage"
	}
	if score >= 0.3 {
		return "save"
	}
	return "skip"
}

// ContentCurator curates top content on a given topic across platforms.
func ContentCurator(ctx context.Context, topic string, count int) (*CuratedContent, error) {
	if count <= 0 {
		count = 10
	}

	var allItems []CuratedItem
	for platform := range platformEndpoints {
		data, err := apiGet(ctx, platform, "/search/posts", map[string]string{
			"q":     topic,
			"limit": fmt.Sprintf("%d", count*2),
			"sort":  "engagement",
		})
		if err != nil {
			log.Printf("ContentCurator: %s failed: %v", platform, err)
			continue
		}

		results, _ := data["results"].([]interface{})
		for _, r := range results {
			post, _ := r.(map[string]interface{})
			engagement := float64(toInt(post["likes"]) + toInt(post["shares"])*2)
			maxEng := math.Max(engagement, 1)
			score := math.Min(engagement/maxEng, 1.0)
			title := fmt.Sprint(post["title"])
			if title == "<nil>" || title == "" {
				title = truncate(fmt.Sprint(post["text"]), 80)
			}

			allItems = append(allItems, CuratedItem{
				SourcePlatform:  platform,
				SourceAuthor:    fmt.Sprint(post["author_name"]),
				Title:           title,
				Summary:         truncate(fmt.Sprint(post["text"]), 280),
				URL:             fmt.Sprint(post["url"]),
				RelevanceScore:  math.Round(score*1000) / 1000,
				EngagementRate:  toFloat(post["engagement_rate"]),
				SuggestedAction: suggestAction(score),
				Tags:            extractStringSlice(post["tags"]),
			})
		}
	}

	sort.Slice(allItems, func(i, j int) bool {
		return allItems[i].RelevanceScore > allItems[j].RelevanceScore
	})

	curated := allItems
	if len(curated) > count {
		curated = curated[:count]
	}

	return &CuratedContent{
		Topic:           topic,
		Items:           curated,
		TotalCandidates: len(allItems),
		CuratedAt:       time.Now().UTC(),
	}, nil
}

// ---------------------------------------------------------------------------
// Tool: TrendAnalyzer
// ---------------------------------------------------------------------------

func computeVelocity(current, previous int) string {
	if previous == 0 {
		return "rising"
	}
	ratio := float64(current) / float64(previous)
	if ratio > 1.5 {
		return "rising"
	}
	if ratio > 0.8 {
		return "peaking"
	}
	return "declining"
}

// TrendAnalyzer analyzes trending topics on a platform within a category.
func TrendAnalyzer(ctx context.Context, platform, category string) (*TrendReport, error) {
	if category == "" {
		category = "general"
	}

	data, err := apiGet(ctx, platform, "/trends", map[string]string{
		"category": category,
		"limit":    "20",
	})
	if err != nil {
		return nil, err
	}

	var trends []TrendEntry
	rawTrends, _ := data["trends"].([]interface{})
	for _, r := range rawTrends {
		t, _ := r.(map[string]interface{})
		volume := toInt(t["volume"])
		prevVolume := toInt(t["previous_volume"])
		if prevVolume == 0 {
			prevVolume = volume
		}
		var hashtag *string
		if h, ok := t["hashtag"].(string); ok && h != "" {
			hashtag = &h
		}
		samples := extractStringSlice(t["sample_posts"])
		if len(samples) > 3 {
			samples = samples[:3]
		}

		trends = append(trends, TrendEntry{
			Name:        fmt.Sprint(t["name"]),
			Hashtag:     hashtag,
			Category:    category,
			Volume:      volume,
			Velocity:    computeVelocity(volume, prevVolume),
			Relevance:   stringOr(t["relevance"], "medium"),
			SamplePosts: samples,
		})
	}

	sort.Slice(trends, func(i, j int) bool {
		return trends[i].Volume > trends[j].Volume
	})

	log.Printf("TrendAnalyzer: %s/%s found %d trends", platform, category, len(trends))

	return &TrendReport{
		Platform:    platform,
		Category:    category,
		Trends:      trends,
		GeneratedAt: time.Now().UTC(),
		PeriodHours: 24,
	}, nil
}

// ---------------------------------------------------------------------------
// Tool: PostScheduler
// ---------------------------------------------------------------------------

// PostScheduler schedules a post for publication on a platform.
func PostScheduler(ctx context.Context, platform, content, scheduleTime string) (*ScheduleResult, error) {
	scheduledDt, err := time.Parse(time.RFC3339, scheduleTime)
	if err != nil {
		errMsg := fmt.Sprintf("invalid schedule time: %v", err)
		return &ScheduleResult{
			Success:        false,
			Platform:       platform,
			ScheduledTime:  time.Now(),
			ContentPreview: truncate(content, 100),
			Error:          &errMsg,
		}, nil
	}

	if _, ok := platformEndpoints[platform]; !ok {
		errMsg := fmt.Sprintf("unsupported platform: %s", platform)
		return &ScheduleResult{
			Success:        false,
			Platform:       platform,
			ScheduledTime:  scheduledDt,
			ContentPreview: truncate(content, 100),
			Error:          &errMsg,
		}, nil
	}

	if scheduledDt.Before(time.Now().UTC()) {
		errMsg := "scheduled time is in the past"
		return &ScheduleResult{
			Success:        false,
			Platform:       platform,
			ScheduledTime:  scheduledDt,
			ContentPreview: truncate(content, 100),
			Error:          &errMsg,
		}, nil
	}

	data, err := apiPost(ctx, platform, "/posts/schedule", map[string]string{
		"content":      content,
		"scheduled_at": scheduleTime,
	})
	if err != nil {
		errMsg := err.Error()
		return &ScheduleResult{
			Success:        false,
			Platform:       platform,
			ScheduledTime:  scheduledDt,
			ContentPreview: truncate(content, 100),
			Error:          &errMsg,
		}, nil
	}

	postID := fmt.Sprint(data["id"])
	if postID == "<nil>" || postID == "" {
		hash := sha256.Sum256([]byte(content))
		postID = fmt.Sprintf("%x", hash[:6])
	}

	log.Printf("PostScheduler: scheduled %s on %s at %s", postID, platform, scheduleTime)

	return &ScheduleResult{
		Success:        true,
		PostID:         &postID,
		Platform:       platform,
		ScheduledTime:  scheduledDt,
		ContentPreview: truncate(content, 100),
	}, nil
}

// ---------------------------------------------------------------------------
// Utility helpers
// ---------------------------------------------------------------------------

func toInt(v interface{}) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	default:
		return 0
	}
}

func toFloat(v interface{}) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case int:
		return float64(n)
	default:
		return 0.0
	}
}

func stringOr(v interface{}, fallback string) string {
	if s, ok := v.(string); ok && s != "" {
		return s
	}
	return fallback
}

func extractStringSlice(v interface{}) []string {
	arr, ok := v.([]interface{})
	if !ok {
		return nil
	}
	out := make([]string, 0, len(arr))
	for _, item := range arr {
		if s, ok := item.(string); ok {
			out = append(out, s)
		}
	}
	return out
}
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Project name for user-agent and logging |
| `{{TWITTER_API_BASE}}` | Twitter/X API base URL |
| `{{TWITTER_API_KEY}}` | Twitter/X bearer token |
| `{{LINKEDIN_API_BASE}}` | LinkedIn API base URL |
| `{{LINKEDIN_API_KEY}}` | LinkedIn access token |
| `{{INSTAGRAM_API_BASE}}` | Instagram Graph API base URL |
| `{{INSTAGRAM_API_KEY}}` | Instagram access token |
| `{{MASTODON_API_BASE}}` | Mastodon instance API base URL |
| `{{MASTODON_API_KEY}}` | Mastodon access token |
