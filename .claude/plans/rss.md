# Plan: RSS Crawler

## Context

The `freechains/crawlers` repo is empty (just LICENSE + README).
We need a Lua RSS/Atom feed parser module and a crawler script
that uses it to produce MH-format RFC 2822 email files,
idempotent for cron usage.

## Dependencies

**No new rocks needed.** Uses only what's installed:
- `luasocket` 3.1.0 (HTTP)
- `luasec` (HTTPS via `ssl.https`)
- `/usr/bin/sha256sum` (Message-ID generation)
- Pure Lua patterns for XML parsing (RSS 2.0 + Atom structures
  are simple enough)

## Files

| File            | Action | Description                          |
|-----------------|--------|--------------------------------------|
| `rss.lua`       | Create | RSS/Atom parser module — Lua table   |
| `crawler.lua`   | Create | CLI script — MH output               |
| `tst/rss.lua`   | Create | Unit tests for rss module            |
| `README.md`     | Update | Usage, examples, sample crontab      |

## Architecture

```
rss.lua (module)          crawler.lua (script)
┌─────────────────┐       ┌──────────────────────┐
│ fetch(url)       │       │ CLI args parsing      │
│ parse(xml)       │──────>│ Deduplication (.seen) │
│   returns table  │       │ MH numbering          │
│                  │       │ RFC 2822 formatting   │
└─────────────────┘       │ File writing           │
                          │ Cron logging (stderr)  │
                          └──────────────────────┘
```

## rss.lua — Module API

```lua
local rss = require("rss")

-- Fetch and parse in one call
local feed, err = rss.get(url)

-- Or separately
local xml, err = rss.fetch(url)
local feed, err = rss.parse(xml)
```

**Returned table structure:**

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
        -- ...
    },
}
```

- `date` is always RFC 2822 format
  (Atom ISO 8601 converted)
- `body` is plain text (HTML stripped, entities decoded)
- `guid` falls back to `link` if absent
- Missing fields default:
  title="(untitled)", date=now, body="", author=feed.title

### Module functions

- `rss.fetch(url)` — HTTP/HTTPS with redirect following
  (up to 5).
  Returns `body, err`.
- `rss.parse(xml)` — Detects RSS 2.0 vs Atom, parses into
  table.
  Returns `feed_table, err`.
- `rss.get(url)` — Convenience: fetch + parse.
  Returns `feed_table, err`.

### Internal helpers (exported via `rss._` for testing)

- `xml_extract(xml, tag)` — tag content, CDATA-aware
- `xml_decode(s)` — XML entity decoding
- `strip_html(s)` — HTML tag removal
- `detect_feed(xml)` — returns `"rss"` or `"atom"`
- `parse_rss(xml)` — RSS 2.0 parser
- `parse_atom(xml)` — Atom parser
- `get_atom_link(entry)` — finds `rel="alternate"` href
- `iso_to_rfc2822(iso)` — ISO 8601 to RFC 2822 conversion

## crawler.lua — CLI Script

### Usage

```
lua crawler.lua <url> <output-dir>
```

- Single feed per invocation
- Exit 0 on success (even if 0 new items)
- Exit 1 on error
- Summary line to stderr: `"feed-title: 3 new, 15 total"`
- Errors to stderr

### Algorithm

```
1. Parse CLI args (url, output_dir)
2. mkdir -p output_dir
3. rss.get(url) → feed table
4. Load <output_dir>/.seen (dedup keys, one per line)
5. Find highest numbered file in output_dir → next MH number
6. For each item:
   a. dedup_key = item.guid (already falls back to link)
   b. Skip if in .seen
   c. Format as RFC 2822 message
   d. Write to <output_dir>/<next_number>
   e. Add to .seen, increment number
7. Save updated .seen
8. Print summary to stderr
```

### Functions

- `load_seen(path)` — reads `.seen` into set table
- `save_seen(path, set)` — writes set back to file
- `next_mh_number(dir)` — scans for highest numeric filename
- `sha256(s)` — calls `/usr/bin/sha256sum` via `io.popen`
- `format_message(item, feed)` — builds RFC 2822 string
- `write_message(dir, number, message)` — writes numbered file
- `main(args)` — orchestrates everything

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

- `.seen` file in `<output-dir>/` stores one dedup key per line
- Key = `guid` (falls back to `link` in the rss module)
- Re-running skips already-seen items
- MH numbering continues from highest existing file

## Edge Cases

| Case                    | Handling                       |
|-------------------------|--------------------------------|
| No guid                 | Module uses link as guid       |
| No link AND no guid     | Module uses sha256(title+date) |
| No title                | "(untitled)"                   |
| No date                 | Current time in RFC 2822       |
| No body                 | Empty string                   |
| CDATA in tags           | CDATA pattern tried first      |
| HTML in description     | Stripped to plain text          |
| First run (.seen missing) | Treated as empty             |
| Feed has 0 items        | Exit 0, no files written       |
| Network/parse error     | stderr message, exit 1         |

## Sample Crontab

```crontab
# Fetch HN newest every 15 minutes
*/15 * * * * lua /x/freechains/crawlers/crawler.lua \
    "https://hnrss.org/newest?count=30" \
    /home/chico/mail/hn \
    2>> /home/chico/log/rss-hn.log

# Fetch Go Blog daily at 6am
0 6 * * * lua /x/freechains/crawlers/crawler.lua \
    "https://go.dev/blog/feed.atom" \
    /home/chico/mail/goblog \
    2>> /home/chico/log/rss-goblog.log
```

## Testing — tst/rss.lua

Plain `assert()` tests, no framework.
Hardcoded XML strings (no network).
Run with: `lua tst/rss.lua`

### Test cases for rss.parse()

**RSS 2.0 parsing:**
1. Minimal RSS feed (1 item with all fields)
   — assert feed.title, feed.link, #items, item fields
2. RSS with CDATA in title and description
   — assert CDATA content extracted correctly
3. RSS with HTML entities (`&amp;`, `&lt;`, `&#38;`)
   — assert decoded to plain characters
4. RSS with HTML tags in description
   — assert tags stripped to plain text
5. RSS item missing guid
   — assert guid falls back to link
6. RSS item missing title
   — assert title = "(untitled)"
7. RSS item missing description
   — assert body = ""
8. RSS with multiple items
   — assert correct count and ordering preserved

**Atom parsing:**
9. Minimal Atom feed (1 entry with all fields)
   — assert feed.title, feed.link, entry fields
10. Atom link with `rel="alternate"` (various attr orders)
    — assert correct href extracted
11. Atom with `<content>` and `<summary>`
    — assert content preferred over summary
12. Atom date ISO 8601 → RFC 2822 conversion
    — assert correct format output
13. Atom entry missing id
    — assert guid falls back to link

**Feed detection:**
14. RSS detected correctly
15. Atom detected correctly
16. Unknown format returns error

**XML helpers:**
17. xml_decode: all entity types
18. strip_html: tags removed, whitespace collapsed

### Test structure

```lua
local function test_rss_minimal() ... end
local function test_rss_cdata() ... end
-- ...

local tests = {
    test_rss_minimal,
    test_rss_cdata,
    -- ...
}
local pass, fail = 0, 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t)
    if ok then
        pass = pass + 1
    else
        fail = fail + 1
        print("FAIL: " .. err)
    end
end
print(pass .. " passed, " .. fail .. " failed")
os.exit(fail > 0 and 1 or 0)
```

Internals exported via `rss._` for testing
(e.g., `rss._.xml_decode`, `rss._.strip_html`).

## Verification

1. `lua tst/rss.lua` → all tests pass
2. `lua crawler.lua <url> <dir>` → manual test with real feed
3. Re-run same command → "0 new" (idempotency check)

## Progress

- [ ] Create rss.lua (module)
- [ ] Create tst/rss.lua (unit tests)
- [ ] Create crawler.lua (script)
- [ ] Update README.md
- [ ] Manual testing
- [ ] CI/CD integration
