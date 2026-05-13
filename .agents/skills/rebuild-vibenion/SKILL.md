---
name: rebuild-vibenion
description: Rebuild and relaunch the local Vibenion macOS app without Xcode. Use when the user asks to rebuild, rerun, restart, or launch Vibenion from Codex.
---

Run the repo-local rebuild script:

```sh
scripts/rebuild-and-run
```

Behavior:

- Builds the SwiftPM executable with `swift build`.
- Stops an existing `Vibenion` process if one is running.
- Launches `.build/debug/Vibenion` detached from the Codex terminal.
- Writes runtime output to `.vibenion/run.log`.

After running it, report whether the command succeeded and include the log path if the user needs runtime output.
