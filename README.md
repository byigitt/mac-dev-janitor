# mac-dev-janitor

Keeps a macOS dev machine that runs many coding agents usable. It has two parts:

- **`daily-clean`**: a daily disk cleanup (LaunchAgent, 20:00 by default).
- **`resource-watchdog`**: a background daemon that kills runaway commands before they freeze the machine, and leaves a note so the agent that started the command does not run it again.

Both run as your user. Neither needs sudo.

## Requirements

- macOS on Apple Silicon or Intel
- `/usr/bin/python3` for the watchdog. It comes with the Xcode Command Line Tools: `xcode-select --install`.
- [Mole](https://github.com/tw93/Mole) for the cleanup: `brew install mole`
- Optional: Docker or OrbStack, Xcode, [t3 Code](https://t3.codes)

## Install

```sh
git clone https://github.com/byigitt/mac-dev-janitor.git
cd mac-dev-janitor
./install.sh                 # both parts, cleanup at 20:00
./install.sh --hour 13       # cleanup at 13:00 instead
./install.sh --agent-rules   # also tell Claude Code / Codex about the watchdog (see below)
```

Other flags: `--no-clean`, `--no-watchdog`, `--no-load`. Run `./uninstall.sh` to remove everything.

Next, grant **Full Disk Access** to `~/Applications/DailyClean.app` in System Settings → Privacy & Security → Full Disk Access. Click +, press Cmd+Shift+G, and paste the path. Without it, the cleanup job can't read repos under `~/Desktop` or `~/Documents`. Those folders are TCC-protected for background jobs. The app is a small wrapper around the script, so the permission applies to this job only and not to every `bash` process.

## daily-clean

The steps run in this order:

1. **Settled t3 worktrees.** A worktree under `~/.t3/worktrees` is removed when it meets one of these:
   - Every t3 thread that uses it has been settled, archived, or deleted for 3+ days.
   - No thread points at it and it has been idle for 14+ days.

   Removal uses `git worktree remove` without `--force`, so a worktree with modified or untracked files is kept. Branches and commits stay in the main repo. The t3 database is opened read-only. The step is skipped if t3 isn't installed.
2. **`mo purge --yes`.** Deletes `node_modules`, `dist`, `target`, and similar folders in projects where no file was modified in the last 7 days. Set the directories it scans with `mo purge --paths`.
3. **`mo clean`.** Clears app caches and logs, the npm, pnpm, bun, and pip caches, Xcode DerivedData, the Homebrew cache, and old browser versions. Paths you added with `mo clean --whitelist` are respected.
4. **Docker cleanup.** Runs `docker system prune --all` and `docker volume prune --all`. This deletes **every** image, container, network, volume, and build cache entry that no running container uses. Remove this step if your volumes hold data you need. It only runs if OrbStack is already running, so it never starts OrbStack.
5. **`xcrun simctl delete unavailable`.** Deletes simulators whose runtime is no longer installed.

When it finishes, it shows a notification with the space freed. The log is in `~/.local/state/daily-clean.log`. Preview a run with `~/.local/bin/daily-clean --dry-run`.

Edit the script to change the thresholds (`T3_SETTLED_DAYS`, `T3_ORPHAN_DAYS`). The LaunchAgent deliberately has no `LowPriorityIO` setting. When I/O is throttled, Mole hits its per-path timeouts and skips those deletions.

## resource-watchdog

Every 10 seconds the watchdog samples `ps` and groups processes by process group. Coding agents run each shell command in its own group, so one group is one command, for example `jest` and all its workers. The watchdog sends the group SIGTERM, then SIGKILL 10 seconds later, when any of these is true:

| Rule | Trigger |
|---|---|
| memory | The group's memory footprint is ≥ 60% of physical RAM (a first Next.js compile alone can pass 9 GB). Or macOS has reported *critical* memory pressure for 30s and this is the largest group (≥ 4 GB). |
| overload | The machine has been ≥ 85% busy for 2 min and the group used ≥ 3 cores in that time. |
| runaway | The group has used ≥ 0.9 cores for 20 min straight. |
| stale | An orphaned dev tool (parent died, no terminal) that is older than 3 h. |

Memory is measured as the physical footprint, the "Memory" column in Activity Monitor. RSS leaves out compressed memory, and compressed memory is where a leaking process on macOS keeps most of its pages.

**Eligible processes:**
- Anything that descends from a coding agent: `omp`, `claude`, `codex`, `cursor-agent`, `opencode`, `gemini`, `amp`, `droid`, `aider`, `goose`.
- A known dev tool (`node`, `bun`, `python`, `vitest`, `jest`, `playwright`, `esbuild`, `cargo`, …) that was started from a terminal or was orphaned.

**Never touched:**
- Groups that contain an agent or a terminal emulator
- App bundles. Editors and their language servers count as app bundles.
- System binaries and launchd jobs
- Shells. When the shell's child is killed, the shell returns exit code 143 to the agent.

Each kill is:
- appended to `~/.local/state/resource-watchdog.log` as JSON lines
- shown as a notification
- printed to the process's terminal if it has one
- for overload, runaway, and memory kills only: appended to `~/.local/state/resource-watchdog-kills.txt` along with the command's working directory and an instruction for the agent.

### Telling agents why their command died

An agent only sees exit code 143 or 137. [`agent-rules.md`](agent-rules.md) tells it to read `resource-watchdog-kills.txt` and to run a smaller command instead of the same one. `./install.sh --agent-rules` appends this file to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`. For other agents, paste it into their global instructions file.

### Tuning

Each value in `CONFIG` at the top of `bin/resource-watchdog` can be overridden with a `WATCHDOG_<NAME>` environment variable. Set it in the LaunchAgent's `EnvironmentVariables`, for example `WATCHDOG_MEMORY_GROUP_GB=12`. To see what the watchdog would kill without killing anything, run `resource-watchdog --dry-run`.

## License

MIT
