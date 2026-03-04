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
        runner.sh       ← test runner
        t_subdir.sh     ← test: URL→subdir
        t_detect.sh     ← test: feed type detection
        t_extract.sh    ← test: jq item extraction
        t_sha256.sh     ← test: sha256 filename
        t_dedup.sh      ← test: idempotency
        t_rfc2822.sh    ← test: message format
        t_pipeline.sh   ← test: end-to-end
        fixtures/
            akita.xml   ← saved akitaonrails feed sample
            hn.xml      ← saved HN official feed sample
            lobster.xml ← saved lobste.rs feed sample
            github.xml  ← saved GitHub Blog Atom sample
README.md               ← update with usage
```

## Architecture

```
rss/crawler.sh <root-dir> <url>
┌─────────────────────────────────────────────────┐
│ 1. Derive subdir from url:                      │
│    https://news.ycombinator.com/rss              │
│    → root-dir/news.ycombinator.com/rss           │
│                                                  │
│ 2. curl -sL <url> | yq -o json -p xml           │
│                                                  │
│ 3. jq: extract items as JSON lines               │
│                                                  │
│ 4. For each item:                                │
│    filename = sha256(guid or link)               │
│    if file exists → skip                         │
│    format RFC 2822 → write to subdir/filename    │
│                                                  │
│ 5. Summary to stderr                             │
└─────────────────────────────────────────────────┘
```

## Directory Structure

Feed URL → domain/path (scheme and query stripped).
Dirs contain only item files (sha256 hashes).

```
root-dir/
    www.akitaonrails.com/
        index.xml/
            a1b2c3d4...   ← sha256(guid)
            f7e8d9c0...
    news.ycombinator.com/
        rss/
            c3d4e5f6...
            d9c0b1a2...
    lobste.rs/
        rss/
            e5f6a1b2...
    github.blog/
        all.atom/
            b3c4d5e6...
```

### URL → subdir derivation

```
https://www.akitaonrails.com/index.xml
  → root-dir/www.akitaonrails.com/index.xml/

https://news.ycombinator.com/rss
  → root-dir/news.ycombinator.com/rss/

https://lobste.rs/rss
  → root-dir/lobste.rs/rss/
```

In shell:
```sh
subdir=$(echo "$url" \
    | sed 's|^https\?://||' \
    | sed 's|?.*||' \
    | sed 's|#.*||' \
    | sed 's|/$||')
item_dir="$root_dir/$subdir"
mkdir -p "$item_dir"
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
rss/crawler.sh <root-dir> <url>
```

- Single feed per invocation
- Exit 0 on success (even if 0 new items)
- Exit 1 on error
- Summary to stderr: `"Feed Title: 3 new, 15 total"`

### Algorithm

```
1. Parse args (root_dir, url)
2. Derive item_dir from url (domain/path)
3. mkdir -p item_dir
4. curl -sL "$url" | yq -o json -p xml > tmp
5. Detect feed type (jq: .rss or .feed)
6. Extract items via jq → one JSON object per line
7. count_new=0, count_total=0
8. For each item:
   a. id = guid or link (skip if neither)
   b. filename = sha256(id)
   c. count_total++
   d. if file exists → skip
   e. Extract: title, link, date, body, author
   f. Format RFC 2822
   g. Write to item_dir/$filename
   h. count_new++
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
    /home/chico/feeds \
    "https://www.akitaonrails.com/index.xml" \
    2>> /home/chico/log/rss.log

# Fetch HN front page every 15 minutes
*/15 * * * * /x/freechains/crawlers/rss/crawler.sh \
    /home/chico/feeds \
    "https://news.ycombinator.com/rss" \
    2>> /home/chico/log/rss.log

# Fetch Lobsters every 30 minutes
*/30 * * * * /x/freechains/crawlers/rss/crawler.sh \
    /home/chico/feeds \
    "https://lobste.rs/rss" \
    2>> /home/chico/log/rss.log

# Fetch GitHub Blog every 2 hours
0 */2 * * * /x/freechains/crawlers/rss/crawler.sh \
    /home/chico/feeds \
    "https://github.blog/all.atom" \
    2>> /home/chico/log/rss.log
```

Result:
```
/home/chico/feeds/
    www.akitaonrails.com/index.xml/...
    news.ycombinator.com/rss/...
    lobste.rs/rss/...
    github.blog/all.atom/...
```

## Incremental Implementation (test-first)

Shell tests with assert-like checks.
XML fixtures for offline testing.
Run: `cd rss && bash tst/runner.sh`

| Step | Test                                     | Implement         |
|------|------------------------------------------|-------------------|
| 1.1  | URL → subdir: strip scheme/query         | subdir derivation |
| 1.2  | URL → subdir: various URL formats        | (edge cases)      |
| 2.1  | yq: akita.xml → valid JSON               | fetch + convert   |
| 2.2  | yq: hn.xml → valid JSON                  | (same)            |
| 2.3  | yq: lobster.xml → valid JSON             | (same)            |
| 2.4  | yq: github.xml → valid JSON              | (same)            |
| 3.1  | jq: detect RSS feed type                 | detect logic      |
| 3.2  | jq: detect Atom feed type                | (same)            |
| 4.1  | jq: extract akita items (all fields)     | extract jq filter |
| 4.2  | jq: extract HN items (no guid)           | (guid fallback)   |
| 4.3  | jq: extract lobster items                | (same filter)     |
| 4.4  | jq: extract GitHub Blog Atom entries     | Atom extract      |
| 4.5  | jq: single item wrapped as array         | (edge case)       |
| 5.1  | sha256: deterministic filename from guid | sha256 func       |
| 5.2  | dedup: first run, all items new          | file-exists check |
| 5.3  | dedup: second run, no new items          | (same)            |
| 6.1  | RFC 2822: valid message format           | format logic      |
| 6.2  | RFC 2822: HTML stripped from body        | (same)            |
| 7.1  | Full pipeline: akita end-to-end          | integration       |
| 7.2  | Full pipeline: HN end-to-end             | integration       |
| 7.3  | Full pipeline: lobster end-to-end        | integration       |
| 7.4  | Full pipeline: GitHub Blog end-to-end    | integration       |

## Verification

1. `cd rss && bash tst/runner.sh` → all tests pass
2. `rss/crawler.sh /tmp/feeds <url>` → manual test
3. Re-run same command → "0 new" (idempotency)

## Progress

- [ ] Install yq
- [ ] Save XML fixtures (akita, hn, lobster, github)
- [ ] Steps 1: URL → subdir
- [ ] Steps 2: yq XML→JSON
- [ ] Steps 3: Detect feed type
- [ ] Steps 4: Extract items (jq filters)
- [ ] Steps 5: sha256 + dedup
- [ ] Steps 6: RFC 2822 formatting
- [ ] Steps 7: Integration tests
- [ ] crawler.sh complete
- [ ] Update README.md
- [ ] Manual testing
- [ ] CI/CD integration
