# Event Schema & Channels

Knowledge Graph stores event streams as newline-delimited JSON (`*.jsonl`).
Multiple streams can coexist via **channels**: each channel gets its own
events file and snapshot file, so domain-specific trackers (e.g. an
"upstream upgrade" watcher) can run in parallel without corrupting the
default work snapshot.

## Files per channel

| Channel         | Events file                     | Snapshot file                 |
|-----------------|---------------------------------|-------------------------------|
| *default* / `work` | `.knowledge-graph/graph-events.jsonl` | `.knowledge-graph/work-snapshot.md` |
| named (e.g. `upgrade`) | `.knowledge-graph/upgrade-events.jsonl` | `.knowledge-graph/upgrade-snapshot.md` |

The default channel is what `track.sh` writes during Claude Code hooks.
Named channels are opt-in and created by callers that want an isolated
stream.

## Event schema (v1)

One event per line. Minimum shape:

```json
{"e": "w:edit", "p": "src/foo.ts", "t": 1776244416}
```

| Field    | Type    | Required | Allowed values / notes |
|----------|---------|----------|------------------------|
| `e`      | string  | yes      | `w:new` (Write), `w:edit` (Edit), `r` (Read), `f` (failure), `i` (InstructionsLoaded) |
| `p`      | string  | yes      | Path relative to project root; non-empty |
| `t`      | number  | yes      | Unix timestamp (seconds) |
| `tool`   | string  | no       | Originating tool name (e.g. `Bash`, `Write`) |
| `err`    | string  | no       | Error message; usually only on `f` events |

Lines failing validation are **silently skipped** by readers (see
tolerance below). Writers must pass validation — `log_channel_event`
validates before appending, so malformed events can't enter the stream.

## Helpers

Shell helpers are provided by `scripts/guard.sh`. Source it with
`CLAUDE_PROJECT_DIR` set, then call:

```bash
# Write a valid event to the "upgrade" channel
log_channel_event upgrade w:edit "pipeline/upstream/cli.js"

# Check validity of a single JSON line
echo '{"e":"w:edit","p":"foo","t":123}' | is_valid_event_line && echo ok

# Strip malformed lines from a stream
cat upgrade-events.jsonl | filter_valid_events
```

## CLI commands

```bash
# Generate a snapshot of a named channel (pure bash, no LLM tokens)
bash analyze.sh save-channel-snapshot upgrade

# Audit a channel's events file — reports valid / invalid counts
bash analyze.sh validate-events upgrade
```

`save-channel-snapshot` writes `{channel}-snapshot.md` containing:

- Event statistics (valid count, dropped count if any)
- Top 8 most-edited files in this channel
- Last 10 events in chronological order
- Last 5 failures, if any

## Tolerance guarantees

Every kg script that reads events does so through `filter_valid_events`
(or an equivalent jq `select(...)`), so:

- Corrupt JSON lines → dropped, no crash
- Lines missing required fields → dropped
- Lines with unknown `e` values → dropped
- Partial writes (e.g. from a killed writer) → dropped

The total line count vs valid line count is surfaced in both
`save-channel-snapshot` and `validate-events` so you can see when
the stream is bleeding bad data.

## When to create a new channel

Create a named channel when your tracker has a scope the default
work channel shouldn't know about — examples:

- **Upstream sync tracker** — events scoped to "Claude Code upstream
  binary changed"; don't mix with general editing activity
- **Test-run analytics** — `tests-events.jsonl` recording pass/fail per test
- **Background agent's activity log** — isolated from the user-facing work snapshot

Do not create a channel just to "organize" — the default `work` channel is
already tagged by path and tool; grouping there is free.
