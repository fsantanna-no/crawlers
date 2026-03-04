# Plan: RSS Crawler

## Context

The `freechains/crawlers` repo is empty (just LICENSE + README).
We need a Lua RSS/Atom feed parser module and a shell crawler
script that produces MH-format RFC 2822 email files,
idempotent for cron usage.

## Dependencies

- `curl` — HTTP/HTTPS fetching
- `yq` (mikefarah) — single Go binary, XML→JSON
- `jq` — installed, JSON processing
- `sha256sum` — installed, Message-ID generation
- `json4lua` 0.9.30 — installed, for Lua module

## Files

| File          | Action | Description                            |
|---------------|--------|----------------------------------------|
| `rss.lua`     | Create | Lua module: JSON→Lua table normalizer  |
| `crawler.sh`  | Create | Shell script: fetch, dedup, MH, RFC2822|
| `tst/rss.lua` | Create | Unit tests for rss.lua module          |
| `README.md`   | Update | Usage, examples, sample crontab        |

## Architecture

```
crawler.sh (shell script)
┌───────────────────────────────────────────┐
│ curl <url>                                │
│   │                                       │
│   ▼                                       │
│ yq -o json -p xml                         │
│   │                                       │
│   ▼                                       │
│ jq (extract items, dedup against .seen)   │
│   │                                       │
│   ▼                                       │
│ for each new item:                        │
│   format RFC 2822 message                 │
│   write to <output-dir>/<number>          │
│   append guid to .seen                    │
│                                           │
│ print summary to stderr                   │
└───────────────────────────────────────────┘

rss.lua (Lua module — reusable from other Lua code)
┌───────────────────────────────────────────┐
│ rss.get(url)                              │
│   curl <url> | yq -o json -p xml          │
│   json.decode()                           │
│   normalize RSS/Atom → common Lua table   │
│                                           │
│ rss.parse(json_str)                       │
│   json.decode() + normalize               │
└───────────────────────────────────────────┘
```

Two independent consumers of the same pipeline:
- `crawler.sh` — standalone, no Lua needed
- `rss.lua` — for Lua projects in freechains ecosystem

## rss.lua — Lua Module API

```lua
local rss = require("rss")

local feed, err = rss.get(url)
local feed, err = rss.parse(json_str)
```

**Returned table:**

```lua
{
    feed = {
        title  = "Hacker News",
        link   = "https://news.ycombinator.com",
    },
    items = {
        {
            title  = "Article Title",
            link   = "https://example.com/article",
            guid   = "https://example.com/article-123",
            date   = "Mon, 03 Mar 2026 14:30:00 +0000",
            body   = "Plain text description...",
            author = "someone",
        },
    },
}
```

- `date` always RFC 2822
  (Atom ISO 8601 converted)
- `body` plain text (HTML stripped)
- `guid` falls back to `link` if absent
- Defaults:
  title="(untitled)", date=now, body="", author=feed.title

### Module functions

- `rss.get(url)` — curl + yq + normalize.
  Returns `feed_table, err`.
- `rss.parse(json_str)` — json.decode + normalize.
  Returns `feed_table, err`.

### Internal helpers (exported via `rss._` for testing)

- `detect_feed(t)` — `t.rss` → "rss", `t.feed` → "atom"
- `normalize_rss(t)` — maps RSS JSON to common table
- `normalize_atom(t)` — maps Atom JSON to common table
- `iso_to_rfc2822(iso)` — ISO 8601 to RFC 2822
- `strip_html(s)` — HTML tag removal

## crawler.sh — Shell Script

```
./crawler.sh <url> <output-dir>
```

- Single feed per invocation
- Exit 0 on success (even if 0 new items)
- Exit 1 on error
- Summary to stderr: `"Feed Title: 3 new, 15 total"`

### Algorithm

```
1. Parse args (url, output_dir)
2. mkdir -p output_dir
3. curl -sL "$url" | yq -o json -p xml > tmp
4. Detect feed type (jq: .rss or .feed)
5. Extract items via jq → one JSON object per line
6. Load .seen (one guid per line)
7. Find highest MH number (ls | sort -n | tail -1)
8. For each item:
   a. guid from jq output
   b. grep -qF "$guid" .seen → skip if found
   c. Format RFC 2822 (printf/heredoc)
   d. Write to output_dir/$next_number
   e. echo "$guid" >> .seen
   f. increment number
9. Print summary to stderr
```

### RFC 2822 Message Format

```
From: <author> <noreply@rss>
Subject: <title>
Date: <RFC 2822 date>
Message-ID: <sha256(guid)@rss>
Content-Type: text/plain; charset=utf-8
X-RSS-Link: <link>
X-RSS-GUID: <guid>

<body>

Link: <link>
```

### Logging (stderr)

- **Success**: `"Feed Title: 3 new, 15 total"`
- **Error**: `"error: <description>"` + exit 1

## Idempotency

- `.seen` file in `<output-dir>/`, one guid per line
- Key = guid (fallback: link)
- Re-running skips seen items
- MH numbering continues from highest existing file

## Edge Cases

| Case                      | Handling                       |
|---------------------------|--------------------------------|
| No guid                   | Use link as guid               |
| No link AND no guid       | sha256(title+date) as guid     |
| No title                  | "(untitled)"                   |
| No date                   | Current time in RFC 2822       |
| No body                   | Empty string                   |
| HTML in description       | Stripped to plain text          |
| First run (.seen missing) | Treated as empty               |
| Feed has 0 items          | Exit 0, no files written       |
| Network/parse error       | stderr message, exit 1         |
| yq/jq not found           | stderr message, exit 1         |
| Single item (not array)   | jq wraps in array              |

## Sample Crontab

```crontab
# Fetch HN newest every 15 minutes
*/15 * * * * /x/freechains/crawlers/crawler.sh \
    "https://hnrss.org/newest?count=30" \
    /home/chico/mail/hn \
    2>> /home/chico/log/rss-hn.log

# Fetch Go Blog daily at 6am
0 6 * * * /x/freechains/crawlers/crawler.sh \
    "https://go.dev/blog/feed.atom" \
    /home/chico/mail/goblog \
    2>> /home/chico/log/rss-goblog.log
```

## Incremental Implementation (test-first)

### rss.lua tests — `tst/rss.lua`

Plain `assert()` tests, no framework.
Hardcoded JSON strings (yq output shape), no network.
Run: `lua tst/rss.lua`

| Step | Test                                       | Implement       |
|------|--------------------------------------------|-----------------|
| 1.1  | strip_html: remove tags, collapse spaces   | strip_html      |
| 1.2  | iso_to_rfc2822: basic ISO 8601             | iso_to_rfc2822  |
| 1.3  | iso_to_rfc2822: with timezone offset       | (extend)        |
| 2.1  | detect_feed: {rss=...} → "rss"            | detect_feed     |
| 2.2  | detect_feed: {feed=...} → "atom"          | (same)          |
| 2.3  | detect_feed: {} → nil, error              | (same)          |
| 3.1  | RSS JSON: 1 item, all fields              | normalize_rss   |
| 3.2  | RSS: missing guid → link fallback         | (edge case)     |
| 3.3  | RSS: missing title → "(untitled)"         | (edge case)     |
| 3.4  | RSS: missing description → body=""        | (edge case)     |
| 3.5  | RSS: single item (object not array)       | (edge case)     |
| 3.6  | RSS: multiple items → count + order       | (edge case)     |
| 3.7  | RSS: HTML in description → stripped       | (edge case)     |
| 4.1  | Atom JSON: 1 entry, all fields            | normalize_atom  |
| 4.2  | Atom: link as object vs array             | (edge case)     |
| 4.3  | Atom: content preferred over summary      | (edge case)     |
| 4.4  | Atom: ISO date → RFC 2822                | (uses helper)   |
| 4.5  | Atom: missing id → link fallback          | (edge case)     |
| 5.1  | rss.parse: RSS JSON string → table        | rss.parse       |
| 5.2  | rss.parse: Atom JSON string → table       | (same)          |
| 5.3  | rss.parse: garbage → nil, error           | (same)          |

### crawler.sh — after rss.lua tests pass

Tested manually with real feeds.

## Verification

1. `lua tst/rss.lua` → all tests pass
2. `./crawler.sh <url> <dir>` → manual test
3. Re-run same command → "0 new" (idempotency)

## Progress

- [ ] Install yq
- [ ] Steps 1.1–1.3: Helpers (test + implement)
- [ ] Steps 2.1–2.3: Feed detection (test + implement)
- [ ] Steps 3.1–3.7: RSS normalization (test + implement)
- [ ] Steps 4.1–4.5: Atom normalization (test + implement)
- [ ] Steps 5.1–5.3: Public API (test + implement)
- [ ] crawler.sh
- [ ] Update README.md
- [ ] Manual testing
- [ ] CI/CD integration
