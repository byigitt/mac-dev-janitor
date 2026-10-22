# Resource watchdog

A local watchdog kills commands that use too much CPU or memory. When a command you ran ends with exit code 143 or 137, `Terminated`, or `Killed`, read the last entries of `~/.local/state/resource-watchdog-kills.txt` (newest last). If one names your command or working directory, the watchdog killed it: do NOT run the same command again. Run a much smaller scope (one test file, `--maxWorkers=2` / `-j2`, no watch mode) or ask the user first.
