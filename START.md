# Goal: Velnor runner as default CI/CD everywhere, all CI green on Velnor

Work autonomously until the done criteria at the end are met. Do not pause for
confirmation. Stop early only for the escalation conditions listed below.

## Context

You run from the control directory `goal/` (this directory). It contains:

- `scripts/repos.txt` — the 36 target repositories across the orgs `jackin-project`, `ChainArgos`, `tailrocks`
- `scripts/audit.sh` — verification script; audits runner defaults + CI status, regenerates `TRACKER.md`
- `TRACKER.md` — auto-generated progress table; never hand-edit, trust it over memory
- `PLAN.md` — phased plan with suggested repo batches

Target repos are cloned (or existing clones reused) under
`/Users/donbeave/Projects/tailrocks/velnor-project/test/green-everything/repositories`.
All changes land via pull requests — never direct pushes to a default branch.

## Objective 1 — Velnor is the default runner for everything

For every repository in `scripts/repos.txt`:

1. Every GitHub Actions workflow runs on the Velnor self-hosted runner fleet by default.
   - Discover the actually registered runner labels before editing — never guess:
     - `gh api orgs/{org}/actions/runners` (org-level fleet)
     - `gh api repos/{owner}/{repo}/actions/runners` (repo-level runners)
   - Velnor lanes use self-hosted labels, e.g. `runs-on: [self-hosted, velnor-target-mvp]`; schemes vary per org/fleet.
2. GitHub-hosted runners (`ubuntu-latest`, `macos-*`, `windows-*`) may exist ONLY as an optional, non-default escape hatch (e.g. a `workflow_dispatch` input selecting a fallback lane). They must never be what runs by default on `push` / `pull_request`.
3. Matrix or expression-based `runs-on: ${{ ... }}`: review manually and convert so the default resolves to Velnor.
4. Repos already fully on Velnor need no PR — verify via the audit and move on.
5. Pre-existing open PRs in these repos: rebase onto the fixed CI, merge when green.

Validate with `scripts/audit.sh --runners-only`: every repo reports `✅ VELNOR`, or `⬜ NO_CI` with a justification in your final report.

## Objective 2 — all CI green on Velnor

For every repository:

1. Latest workflow runs on the default branch: all successful AND executed on the Velnor fleet.
2. All open PRs: checks green AND executed on the Velnor fleet.
3. Fix failures at the root cause (runner environment, missing tooling, permissions, network egress, secrets, caching). Never mask failures with retries, `continue-on-error`, or deleted tests.

Validate with `scripts/audit.sh`: every repo row shows main `✅ GREEN` running on `velnor`, and PRs all green.

## Hard rules — never violate

- **Never use admin privileges to merge.** No `gh pr merge --admin`, no bypassing branch protection, no merging over red checks. If a required check blocks a merge, fix the check. Updating branch protection's *required check list* to match renamed workflows is allowed; weakening or disabling protection to force a merge is not.
- **Velnor is always the default.** GitHub-hosted runners may be used only as a temporary fallback when the Velnor fleet is down (e.g. to land an urgent fix). Any such use must be reverted afterwards and called out in your final report.
- One PR per repo per logical change. Conventional commit messages. Always commit with DCO signoff: `git commit -s`.
- Never disable or delete a workflow just to make CI green. Fix it, or remove it only with justification in the PR description.
- Never print, exfiltrate, or commit secrets/credentials.

## Operating procedure

Orchestrate only. The main loop never clones, edits, or watches CI — dispatch subagents and keep the main context lean.

1. Run `scripts/audit.sh` to refresh `TRACKER.md` from live GitHub state. Commit and push the control repo (`git commit -s`).
2. Pick the next batch (up to 5) of repos in `TRACKER.md` not fully ✅.
3. Dispatch one subagent per repo, in parallel. Each subagent must:
   - Clone the repo into the `repositories/` dir above (or reuse the existing clone).
   - Audit `.github/workflows/*`; discover the real Velnor labels via the `gh api` calls above.
   - Convert `runs-on` to Velnor labels on a branch; open a PR (subagents are always authorized to create and merge PRs).
   - Watch checks, iterate until green, merge without admin override (`gh pr merge --squash` or `--auto --squash`).
   - Return only a short report (≤10 lines): PR links, final status, blockers/follow-ups.
4. Re-run `scripts/audit.sh`; confirm the tracker rows flip. Commit and push.
5. Repeat until all 36 repos satisfy both objectives.

**Blocked repos do not halt the run.** Record the blocker, move on to other repos, list it in the final report. Halt the whole run only for global blockers: `gh` auth lost, Velnor fleet down, or org-wide secrets/config you lack.

## Escalate to the user (stop and ask) when

- CI on Velnor needs new secrets or org-level config you cannot create.
- A global blocker above persists.
- A repo requires weakening branch protection or deleting CI to go green and no fix exists.

## Done criteria

- `scripts/audit.sh` reports every repo: runner default `✅ VELNOR` (or justified `⬜ NO_CI`), main `✅ GREEN` on `velnor`, open PRs all green.
- `TRACKER.md` fully green and committed.
- Final report: totals, every exception justified (e.g. `⬜ NO_CI` repos), fallback incidents, remaining follow-ups.

First action: step 1 — run the baseline audit.
