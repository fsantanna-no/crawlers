# Plan: RSS Crawler

## Context

The `freechains/crawlers` repo is empty (just LICENSE + README).
We need a shell crawler script that fetches RSS/Atom feeds and
saves items as RFC 2822 files, idempotent for cron.

## Dependencies

- `curl` — HTTP/HTTPS fetching
- `yq` (mikefarah) — single Go binary, XML→JSON
- `jq` — installed, JSON processing
- `sha256sum` — installed, item filenames + Message-ID

## File Layout

Everything lives under `rss/`:

```
rss/
    crawler.sh          ← main script
    tst/
        Makefile        ← test runner
        detect.sh       ← test: feed type detection
        extract.sh      ← test: jq item extraction
        sha256.sh       ← test: sha256 filename
        dedup.sh        ← test: idempotency
        rfc2822.sh      ← test: message format
        pipeline.sh     ← test: end-to-end
        fixtures/
            akita.xml   ← saved akitaonrails feed sample
            hn.xml      ← saved HN official feed sample
            lobster.xml ← saved lobste.rs feed sample
            github.xml  ← saved GitHub Blog Atom sample
README.md               ← update with usage
```

## Architecture

```
rss/crawler.sh <output-dir> <url>
┌─────────────────────────────────────────────────┐
│ 1. mkdir -p <output-dir>                         │
│                                                  │
│ 2. curl -sL <url> | yq -o json -p xml           │
│                                                  │
│ 3. jq: extract items as JSON lines               │
│                                                  │
│ 4. For each item:                                │
│    filename = sha256(guid or link)               │
│    if file exists → skip                         │
│    format RFC 2822 → write to output-dir/filename│
│                                                  │
│ 5. Summary to stderr                             │
└─────────────────────────────────────────────────┘
```

## Directory Structure

User decides the output directory explicitly.
Each dir contains only item files (sha256 hashes).

```
/home/chico/feeds/
    akita/
        a1b2c3d4...   ← sha256(guid)
        f7e8d9c0...
    hn/
        c3d4e5f6...
        d9c0b1a2...
    lobster/
        e5f6a1b2...
    github/
        b3c4d5e6...
```

## Idempotency — sha256(guid) as filename

No `.seen` file needed.
The filesystem IS the dedup mechanism.

- **filename** = `sha256(guid)`, 64 hex chars
- **guid** stored inside the file as `X-RSS-GUID` header
- **New item**: file doesn't exist → write it
- **Seen item**: file exists → skip
- **Edited item**: same guid → same hash → overwrites

### Guid fallback

1. RSS `<guid>` or Atom `<id>` → sha256 it
2. If missing → use `<link>` → sha256 it
3. If both missing → skip item

Note: official HN RSS has no `<guid>`.
Fallback to `<link>` (article URL) works.

### Cron scenario

```
First run:   dir empty      → all 10 items written
Second run:  10 files exist → 2 new items written
Third run:   12 files exist → 0 new, nothing written
```

## crawler.sh

```
rss/crawler.sh <output-dir> <url>
```

- Single feed per invocation
- Exit 0 on success (even if 0 new items)
- Exit 1 on error
- Summary to stderr: `"Feed Title: 3 new, 15 total"`

### Algorithm

```
1. Parse args (output_dir, url)
2. mkdir -p output_dir
3. curl -sL "$url" | yq -o json -p xml > tmp
4. Detect feed type (jq: .rss or .feed)
5. Extract items via jq → one JSON object per line
6. count_new=0, count_total=0
7. For each item:
   a. id = guid or link (skip if neither)
   b. filename = sha256(id)
   c. count_total++
   d. if file exists → skip
   e. Extract: title, link, date, body, author
   f. Format RFC 2822
   g. Write to output_dir/$filename
   h. count_new++
8. Print summary to stderr
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

## Test Feeds

| Feed                                    | Format  | guid        | Notes                        |
|-----------------------------------------|---------|-------------|------------------------------|
| https://www.akitaonrails.com/index.xml  | RSS 2.0 | URL         | content:encoded, HTML body   |
| https://news.ycombinator.com/rss        | RSS 2.0 | **missing** | fallback to link, CDATA desc |
| https://lobste.rs/rss                   | RSS 2.0 | short URL   | author, categories           |
| https://github.blog/all.atom            | Atom    | tag URI     | Atom path (entries, not items)|

Saved as XML fixtures in `rss/tst/fixtures/` for offline
testing.

## Edge Cases

| Case                     | Handling                  |
|--------------------------|---------------------------|
| No guid                  | sha256(link) as filename  |
| No guid AND no link      | Skip item                 |
| No title                 | "(untitled)"              |
| No date                  | Current time in RFC 2822  |
| No body                  | Empty string              |
| HTML in description      | Stripped to plain text     |
| Feed has 0 items         | Exit 0, no files written  |
| Network/parse error      | stderr message, exit 1    |
| yq/jq not found          | stderr message, exit 1    |
| Single item (not array)  | jq wraps in array         |

## Sample Crontab

```crontab
# Fetch Akita on Rails every hour
0 * * * * /x/freechains/crawlers/rss/crawler.sh \
    /home/chico/feeds/akita \
    "https://www.akitaonrails.com/index.xml" \
    2>> /home/chico/log/rss.log

# Fetch HN front page every 15 minutes
*/15 * * * * /x/freechains/crawlers/rss/crawler.sh \
    /home/chico/feeds/hn \
    "https://news.ycombinator.com/rss" \
    2>> /home/chico/log/rss.log

# Fetch Lobsters every 30 minutes
*/30 * * * * /x/freechains/crawlers/rss/crawler.sh \
    /home/chico/feeds/lobster \
    "https://lobste.rs/rss" \
    2>> /home/chico/log/rss.log

# Fetch GitHub Blog every 2 hours
0 */2 * * * /x/freechains/crawlers/rss/crawler.sh \
    /home/chico/feeds/github \
    "https://github.blog/all.atom" \
    2>> /home/chico/log/rss.log
```

Result:
```
/home/chico/feeds/
    akita/...
    hn/...
    lobster/...
    github/...
```

## Incremental Implementation (test-first)

Shell tests with assert-like checks.
XML fixtures for offline testing.
Run: `cd rss && make -C tst`

| Step | Test                                     | Implement         |
|------|------------------------------------------|-------------------|
| 1.1  | yq: akita.xml → valid JSON               | fetch + convert   |
| 1.2  | yq: hn.xml → valid JSON                  | (same)            |
| 1.3  | yq: lobster.xml → valid JSON             | (same)            |
| 1.4  | yq: github.xml → valid JSON              | (same)            |
| 2.1  | jq: detect RSS feed type                 | detect logic      |
| 2.2  | jq: detect Atom feed type                | (same)            |
| 3.1  | jq: extract akita items (all fields)     | extract jq filter |
| 3.2  | jq: extract HN items (no guid)           | (guid fallback)   |
| 3.3  | jq: extract lobster items                | (same filter)     |
| 3.4  | jq: extract GitHub Blog Atom entries     | Atom extract      |
| 3.5  | jq: single item wrapped as array         | (edge case)       |
| 4.1  | sha256: deterministic filename from guid | sha256 func       |
| 4.2  | dedup: first run, all items new          | file-exists check |
| 4.3  | dedup: second run, no new items          | (same)            |
| 5.1  | RFC 2822: valid message format           | format logic      |
| 5.2  | RFC 2822: HTML stripped from body        | (same)            |
| 6.1  | Full pipeline: akita end-to-end          | integration       |
| 6.2  | Full pipeline: HN end-to-end             | integration       |
| 6.3  | Full pipeline: lobster end-to-end        | integration       |
| 6.4  | Full pipeline: GitHub Blog end-to-end    | integration       |

## Verification

1. `cd rss && make -C tst` → all tests pass
2. `rss/crawler.sh /tmp/feeds <url>` → manual test
3. Re-run same command → "0 new" (idempotency)

## Progress

- [x] Install yq
- [x] Save XML fixtures (akita, hn, lobster, github)
- [x] Skeleton crawler.sh (shebang, arg parsing)
- [ ] Steps 1: yq XML→JSON
- [ ] Steps 2: Detect feed type
- [ ] Steps 3: Extract items (jq filters)
- [ ] Steps 4: sha256 + dedup
- [ ] Steps 5: RFC 2822 formatting
- [ ] Steps 6: Integration tests
- [ ] crawler.sh complete
- [ ] Update README.md
- [ ] Manual testing
