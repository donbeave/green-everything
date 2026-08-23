# RESUME — Goal Prompt for `/goal` (resume after interruption)

Paste everything below the separator line into `/goal`.

---

## Resume goal: Velnor runner as default CI/CD everywhere, all CI green on Velnor

This is a resumption of the goal fully defined in `START.md` (same directory). Read `START.md` first. All its hard rules still bind — especially: never merge with admin privileges, never bypass branch protection, Velnor is always the default runner, DCO signoff on commits.

Resume procedure:

1. Run `scripts/audit.sh` to regenerate `TRACKER.md` from live GitHub state. Trust the tracker over any prior memory or summary.
2. Close out in-flight PRs first: dispatch a subagent per repo with open PRs (`gh pr list -R owner/repo`) to check status, rebase/fix if needed, merge when green — no admin override.
3. Continue the `START.md` working loop from the first repo in `TRACKER.md` not fully ✅.
4. Re-run `scripts/audit.sh` after each merge.

Done criteria unchanged: every repo row in `TRACKER.md` shows runner default `✅ VELNOR` (or justified `⬜ NO_CI`), main `✅ GREEN` on `velnor`, and all open PRs green.

Begin with step 1: run the audit.
