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
- Jump-to-terminal targeting from session event metadata
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

For exact jump-back behavior, include `terminal_metadata` with the terminal app
and window identity:

```json
{"session_id":"codex-api","agent":"codex","state":"running","summary":"Running tests","title":"api cleanup","terminal":"Ghostty","terminal_metadata":{"app_name":"Ghostty","bundle_id":"com.mitchellh.ghostty","pid":9123,"window_id":77,"window_title":"vibenion"}}
```

For cmux, include workspace/surface metadata so Vibenion can select the exact pane:

```json
{"session_id":"codex-api","agent":"codex","state":"running","summary":"Running tests","title":"api cleanup","terminal":"cmux","terminal_metadata":{"workspace_id":"workspace:2","surface_id":"surface:4","socket_path":"/tmp/cmux.sock"}}
```

For Codex Desktop, Vibenion uses the Codex thread id from discovery or
`terminal_metadata.thread_id` to open the app's local-conversation deep link:
`codex://local/<thread_id>`. If the deep link cannot be opened, it falls back to
focusing Codex and trying the local app-server/visible-sidebar paths.

```json
{"session_id":"019e0850-8f41-7e90-b6c9-a67946f7b2a7","agent":"codex","state":"running","summary":"Running tests","title":"api cleanup","terminal":"Codex","terminal_metadata":{"bundle_id":"com.openai.codex","thread_id":"019e0850-8f41-7e90-b6c9-a67946f7b2a7"}}
```

Supported terminal app bundle IDs:

- Ghostty: `com.mitchellh.ghostty`
- iTerm2: `com.googlecode.iterm2`
- Terminal: `com.apple.Terminal`
- Codex App: `com.openai.codex`

States:

- `running`
- `approval`
- `question`
- `done`

Helper script:

```sh
scripts/vibenion-event codex-api codex running "Running tests" "api cleanup" Terminal 2m "bun test started"
scripts/vibenion-event codex-api codex running "Running tests" "api cleanup" Ghostty 2m "bun test started" '{"bundle_id":"com.mitchellh.ghostty","window_id":77}'
scripts/vibenion-event codex-api codex running "Running tests" "api cleanup" cmux 2m "bun test started" '{"workspace_id":"workspace:2","surface_id":"surface:4"}'
scripts/vibenion-event codex-api codex approval "Approve edit in src/server.ts" "api cleanup" Terminal 3m "Patch pending"
scripts/vibenion-event codex-api codex done "Tests passed" "api cleanup" Terminal 5m "Ready for review"
```

## Next

- Codex session discovery
- Ambient pet attention surface
- Real approval/question bridge
- Preferences persistence

## License

MIT
