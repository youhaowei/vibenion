# Vibenion — Claude notes

## Rebuild + run

After code changes, run:

```
./scripts/rebuild-and-run
```

This builds the SwiftPM target, kills any existing `Vibenion` process, and launches the new binary in the background (log at `.vibenion/run.log`). No manual relaunch needed.

## Architecture

- **Discovery layers** (file-system + process tree)
  - `ClaudeSessionDiscovery` — reads `~/.claude/sessions/*.json` (active) and `~/.claude/projects/*/sessions-index.json` (history). JSONL transcript mtime in `~/.claude/projects/<encoded-cwd>/<sessionID>.jsonl` is the ground truth for "is Claude generating right now" (status field lags).
  - `CodexSessionDiscovery` — Codex thread files.
  - `CmuxSessionDiscovery` — cmux process tree, maps PIDs to terminal tabs.
- **Aggregation** — `AgentSessionStore` polls discovery every 5s, merges with event-log entries, filters non-jumpable sessions (no `terminalTarget`).
- **UI** — `IslandRootView` renders the notch island; `SessionRow` per session, grouped into `attention` / `running` / `idleOrDone`.

## State model

Five states: `asking`, `working`, `ready`, `idle`, `done`.

- `asking` + `ready` both count as `needsHuman` (agent waiting on user — explicit question vs at-prompt).
- `acknowledgedAt` set on jump or dismiss; cleared when state changes. `needsAttention` = `needsHuman && acknowledgedAt == nil`.
- Sessions without `terminalTarget` are filtered out (no jump path → no row).

## Conventions

- Session sort: within a group, prefer chronological (most recent first) over state-priority — keeps acknowledged rows from bubbling above truly older ones.
- Empty `summary` → row collapses to single-line. Don't synthesize metadata-shaped summaries; leave blank until real prompt/action content is plumbed.
