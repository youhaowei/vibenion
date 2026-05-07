# Vibenion

Native macOS attention surface for local agent-driven work.

Vibenion watches local AI-agent activity and keeps the important bits visible:
what is running, what finished, what looks stale, and where to jump back in.
It is intentionally local-first and currently focused on Claude Code, with Codex
support planned next.

Vibenion is separate from Workforce. Workforce is the durable task cockpit and
agent control plane; Vibenion is the lightweight macOS surface for attention.

## Status

Experimental. Expect rough edges.

## Run

```sh
swift build
swift test
swift run Vibenion
```

## Current Slice

- Floating non-activating notch panel
- Menu bar toggle
- Real Claude Code session discovery from `~/.claude/sessions/*.json`
- Running/idle/stale/done state mapping
- Repo and branch context from session `cwd`
- Approval and question action placeholders
- Jump-to-terminal placeholder
- Local JSONL event ingestion from `~/.vibenion/events.jsonl`

## Claude Session Discovery

Vibenion reads Claude Code session metadata from:

```sh
~/.claude/sessions/*.json
```

The current list uses `sessionId`, `pid`, `cwd`, `status`, `startedAt`, `updatedAt`,
and optional `name` fields to show live Claude sessions, repo/worktree context, branch,
and running/idle/stale/done state.

## Event Ingestion

Vibenion watches this file:

```sh
~/.vibenion/events.jsonl
```

Append one JSON object per line:

```json
{"session_id":"codex-api","agent":"codex","state":"running","summary":"Running tests","title":"api cleanup","terminal":"Terminal","elapsed":"2m","message":"bun test started"}
```

States:

- `running`
- `approval`
- `question`
- `done`

Helper script:

```sh
scripts/vibenion-event codex-api codex running "Running tests" "api cleanup" Terminal 2m "bun test started"
scripts/vibenion-event codex-api codex approval "Approve edit in src/server.ts" "api cleanup" Terminal 3m "Patch pending"
scripts/vibenion-event codex-api codex done "Tests passed" "api cleanup" Terminal 5m "Ready for review"
```

## Next

- Terminal window targeting
- Codex session discovery
- Ambient pet attention surface
- Real approval/question bridge
- Preferences persistence

## License

MIT
