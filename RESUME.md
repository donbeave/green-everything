# Resume: Velnor CI green everywhere

This resumes an interrupted run of the goal defined in @GOAL.md. Everything in
that file — context, objectives, hard rules, operating procedure, escalation
conditions, done criteria — binds.

You have no reliable memory of prior progress. Rebuild state from live sources,
never from summaries. Recovery procedure, before any new work:

1. Run `scripts/audit.sh` to regenerate `TRACKER.md` from live GitHub state. Commit and push the control repo.
2. Reconcile interrupted work:
   - For every repo with open PRs (`gh pr list -R owner/repo`): dispatch one subagent per repo to check status, rebase/fix if needed, merge when green — no admin override.
   - Stale local branches under `/Users/donbeave/Projects/tailrocks/velnor-project/test/green-everything/repositories` left by a dead subagent: push the branch to origin before resetting or deleting anything. Never destroy unmerged work.
3. Resume the operating procedure in @GOAL.md from the first repo in `TRACKER.md` not fully ✅.
4. Re-run `scripts/audit.sh` after each merge; commit and push `TRACKER.md`.

First action: step 1 — run the audit.
