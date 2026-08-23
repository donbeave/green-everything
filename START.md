# START — Goal Prompt for `/goal`

Paste everything below the separator line into `/goal`.

---

## Goal: Velnor runner as default CI/CD everywhere, all CI green on Velnor

You are working from the control directory `goal/` (this directory). It contains:

- `scripts/repos.txt` — the 36 target repositories across the orgs `jackin-project`, `ChainArgos`, `tailrocks`
- `scripts/audit.sh` — verification script; audits runner defaults + CI status, regenerates `TRACKER.md`
- `TRACKER.md` — auto-generated progress table (never hand-edit)
- `PLAN.md` — phased plan

### Goal 1 — Velnor is the default runner for everything

For every repository in `scripts/repos.txt`:

1. Every GitHub Actions workflow must run on the Velnor self-hosted runner fleet by default.
   - Velnor lanes use self-hosted labels, e.g. `runs-on: [self-hosted, velnor-target-mvp]`. Label schemes may vary per org/fleet — always confirm the actually registered runner labels first:
     - `gh api orgs/{org}/actions/runners` (org-level fleet)
     - `gh api repos/{owner}/{repo}/actions/runners` (repo-level runners)
   - Use the labels you find; do not guess.
2. GitHub-hosted runners (`ubuntu-latest`, `macos-*`, `windows-*`) are allowed ONLY as an optional, non-default escape hatch (e.g. a `workflow_dispatch` input selecting a fallback lane). They must never be what runs by default on `push` / `pull_request`.
3. Matrix or expression-based `runs-on: ${{ ... }}` must be reviewed manually and converted so the default resolves to Velnor.
4. Open PRs in these repos may be merged while working on this goal: rebase them onto the fixed CI, merge when green.

Validate with `scripts/audit.sh --runners-only`: every repo must report `✅ VELNOR`, or `⬜ NO_CI` with a justification in your final report.

### Goal 2 — all CI green on Velnor

For every repository:

1. Latest workflow runs on the default branch: all successful AND executed on the Velnor fleet.
2. All open PRs: checks green AND executed on the Velnor fleet.
3. Fix failures at the root cause (runner environment, missing tooling, permissions, network egress, secrets, caching). Do not mask failures with retries, `continue-on-error`, or deleted tests.

Validate with `scripts/audit.sh`: every repo row shows main `✅ GREEN` running on `velnor`, and PRs all green.

### Hard rules — never violate

- **Never use admin privileges to merge.** No `gh pr merge --admin`, no bypassing branch protection, no merging over red checks. If a required check blocks a merge, fix the check. Updating branch protection's *required check list* to match renamed workflows is allowed; weakening or disabling protection to force a merge is not.
- **Velnor is always the default.** GitHub-hosted runners may be used only as a temporary fallback when the Velnor fleet is down (e.g. to land an urgent fix). Any such use must be reverted afterwards and called out in your final report.
- One PR per repo per logical change. Conventional commit messages. Always commit with DCO signoff: `git commit -s`.
- Never disable or delete a workflow just to make CI green. Fix it, or remove it only with justification in the PR description.
- Never print, exfiltrate, or commit secrets/credentials. If CI on Velnor needs new secrets or org-level config you lack, stop and ask the user.

### Working loop

1. Run `scripts/audit.sh` to refresh `TRACKER.md` from live GitHub state. Trust it over memory.
2. Pick the next batch of repos in `TRACKER.md` not fully ✅.
3. Dispatch one subagent per repo — always subagents, never do repo work in the main loop; keep the main context window lean. Each subagent: audits the repo's workflows, clones, converts `runs-on` to the Velnor labels, opens a PR, watches checks, iterates until green, merges without admin override (`gh pr merge --squash` or `--auto --squash`), and returns only a short report (PR links, final status, follow-ups). Run independent repos in parallel subagents.
4. Re-run `scripts/audit.sh`; confirm the tracker rows flip.
5. Repeat until all 36 repos satisfy Goal 1 and Goal 2.

### Done criteria

- `scripts/audit.sh` reports every repo: runner default `✅ VELNOR` (or justified `⬜ NO_CI`), main `✅ GREEN` on `velnor`, open PRs all green.
- `TRACKER.md` fully green; every exception (e.g. `⬜ NO_CI` repos) justified in your final report.

Start now with step 1 of the working loop: run the baseline audit.
