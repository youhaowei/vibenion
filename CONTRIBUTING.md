# Contributing

Vibenion is early and experimental. The main goal is a reliable local macOS
attention surface for agent-driven work.

## Development

```sh
swift build
swift test
swift run Vibenion
```

## Scope

Good first contributions stay close to:

- Claude Code session discovery
- Codex session discovery
- local-only session/intervention modeling
- macOS attention surfaces
- terminal/worktree jump-back behavior

Avoid turning Vibenion into a task manager or orchestration system. Workforce is
the intended durable task cockpit and control plane.

## Privacy

Do not commit local session data, transcripts, Claude/Codex config, or generated
files from `~/.claude`, `~/.codex`, or `~/.vibenion`.
