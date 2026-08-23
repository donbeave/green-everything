# PLAN — Velnor CI Green Everywhere

Execution plan backing `START.md`. The `/goal` agent follows the `START.md` working loop; this plan is the phase-level view.

## Phase 0 — Baseline

- Verify tooling: `gh auth status`, `jq` present.
- Run `scripts/audit.sh` for a full baseline.

## Phase 1 — Fleet label discovery

- Per org (`jackin-project`, `ChainArgos`, `tailrocks`): `gh api orgs/{org}/actions/runners` to enumerate the Velnor fleet and its labels.
- Use the discovered labels for all conversions (e.g. `[self-hosted, velnor-target-mvp]`) — never guessed ones.

## Phase 2 — Goal 1: Velnor default runner (36 repos)

Repo-by-repo, in tracker order:

1. Audit `.github/workflows/*` on the default branch.
2. Convert `runs-on` to Velnor labels; keep GitHub-hosted lanes only as non-default escape hatches (`workflow_dispatch` input), if desired at all.
3. PR per repo; green checks; merge without admin override.
4. Repos with no CI: justify the `NO_CI` status in the final report. (Decide per repo whether CI should be added — if the repo ships code, propose minimal Velnor CI in a PR.)

Suggested batches (similar CI shapes convert faster together):

- Homebrew taps: `homebrew-tap`, `homebrew-holla`, `homebrew-tablerock`, `homebrew-parallax`, `homebrew-ruxel`
- Terraform/OpenTofu: `jackin-github-terraform`, `github-terraform` (×2), `cloudflare-tofu` (×2)
- Velnor actions/runner infra: `velnor-actions` (×3), `velnor-actions-fixture`, `velnor`, `velnor-apt`
- Jackin tooling: `jackin`, `jackin-the-architect`, `jackin-role-action`, `jackin-sentinel`, `jackin-agent-smith`, `jackin-agent-brown`, `jackin-dev`
- Tailrocks product/libs: `holla`, `holla-apt`, `termrock`, `tablerock`, `parallax`, `ruxel`, `tracing-request-level`, `pg-bigdecimal`, `schemalane`, `parallax-telemetry-playground`, `tailrocks-skills`, `velnor-apt`
- ChainArgos: `java-monorepo`, `blockchain-nodes`

## Phase 3 — Goal 2: all green on Velnor

- For each repo red on main or PRs: diagnose on the Velnor runner (missing tooling, Docker availability, network egress, secrets, permissions).
- Fix root causes; escalate environment gaps into the `velnor` repo itself if the runner image/tooling is the cause.
- Triage and land open PRs: rebase onto fixed CI, merge when green.

## Phase 4 — Final validation

- Full `scripts/audit.sh` run: all rows ✅.
- Final report covers: exceptions, fallback incidents, remaining follow-ups.
- Spot-check merge compliance: recent merges done without admin override (PR pages show checks passed before merge).
