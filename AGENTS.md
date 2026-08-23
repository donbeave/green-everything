# AGENTS.md

1. **Always commit and push your work.** After every meaningful change: `git commit -s`
   (DCO signoff) and `git push`. Never leave work uncommitted or unpushed.
2. **Never stop until the goal is fully achieved.** Keep iterating until the goal in
   `START.md` is complete. Do not pause for confirmation.
3. **Always use subagents for each unit of work; keep the main context window lean.**
   The main loop orchestrates only: run `scripts/audit.sh`, read `TRACKER.md`, dispatch one
   subagent per repo/task, collect their short final reports. All cloning, editing, CI
   watching, and merging happens inside subagents. The main context never holds file dumps
   or logs — only subagent summaries.
4. **Clone every target repository locally under
   `/Users/donbeave/Projects/tailrocks/velnor-project/test/green-everything/repositories`.**
   All changes land via pull requests — never direct pushes to the default branch. Subagents
   are always authorized to create and merge PRs to achieve their assigned task (still no
   admin override, checks must be green).
