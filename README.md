# Velnor CI Green Everywhere — control room

Goal: make the Velnor self-hosted runner the default CI/CD runner across 36 repositories
(`jackin-project`, `ChainArgos`, `tailrocks`), then make every default branch and every open PR
green on Velnor. Never merge with admin privileges; GitHub-hosted runners are an optional,
non-default fallback only.

## Files

| File | Purpose |
|------|---------|
| `START.md` | Full goal prompt — paste into `/goal` to start |
| `RESUME.md` | Resume prompt — paste into `/goal` after interruption |
| `PLAN.md` | Phased execution plan |
| `TRACKER.md` | Auto-generated progress table (do not hand-edit) |
| `scripts/repos.txt` | The 36 target repositories |
| `scripts/audit.sh` | Verification: runner defaults + CI status → regenerates `TRACKER.md` |

## Usage

```bash
scripts/audit.sh                  # full audit, rewrites TRACKER.md
scripts/audit.sh --runners-only   # Goal 1 check only (fast)
scripts/audit.sh --ci-only        # Goal 2 check only
scripts/audit.sh --repo tailrocks/velnor --no-write   # single repo, print only
```

Requires: `gh` (authenticated, access to all three orgs), `jq`.

## Start / resume

- Start: paste contents of `START.md` (below its separator line) into `/goal`.
- Resume: paste contents of `RESUME.md` into `/goal`.
