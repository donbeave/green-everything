# Resume goal: Velnor runner as default CI/CD everywhere, all CI green on Velnor

This resumes an interrupted run of the goal fully defined in `START.md` (same
directory). Read `START.md` first — it is the source of truth. Its objectives,
hard rules, operating procedure, and done criteria all still bind (especially:
never merge with admin privileges, Velnor always the default runner, DCO
signoff on commits).

You have no reliable memory of prior progress. Rebuild state from live sources,
never from summaries:

1. Run `scripts/audit.sh` to regenerate `TRACKER.md` from live GitHub state. Commit and push the control repo.
2. Reconcile interrupted work before starting new work:
   - For every repo with open PRs (`gh pr list -R owner/repo`): dispatch one subagent per repo to check status, rebase/fix if needed, merge when green — no admin override.
   - Stale local branches under `/Users/donbeave/Projects/tailrocks/velnor-project/test/green-everything/repositories` left by a dead subagent: push the branch to origin before resetting or deleting anything. Never destroy unmerged work.
3. Resume the `START.md` operating procedure from the first repo in `TRACKER.md` not fully ✅.
4. Re-run `scripts/audit.sh` after each merge; commit and push `TRACKER.md`.

Done criteria: exactly as defined in `START.md`.

First action: step 1 — run the audit.
