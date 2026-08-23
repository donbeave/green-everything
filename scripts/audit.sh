#!/usr/bin/env bash
# audit.sh — audit Velnor-runner default + CI green status for all repos in scripts/repos.txt
# Usage: scripts/audit.sh [--runners-only] [--ci-only] [--no-labels] [--no-write] [--repo owner/name]
#
# Output: markdown table on stdout; rewrites TRACKER.md unless --no-write.
#   --runners-only   only classify workflow runs-on defaults (Goal 1)
#   --ci-only        only check main-branch runs + open PR status (Goal 2)
#   --no-labels      skip per-run job label lookups (faster, less API usage)
#   --no-write       print only, do not touch TRACKER.md
#   --repo o/r       audit a single repo (testing)
#
# Requires: gh (authenticated), jq.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_FILE="$ROOT/scripts/repos.txt"
TRACKER="$ROOT/TRACKER.md"

MODE_RUNNERS=1
MODE_CI=1
LABELS=1
WRITE=1
ONLY_REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runners-only) MODE_CI=0 ;;
    --ci-only)      MODE_RUNNERS=0 ;;
    --no-labels)    LABELS=0 ;;
    --no-write)     WRITE=0 ;;
    --repo)         ONLY_REPO="${2:-}"; shift ;;
    -h|--help)      sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v gh >/dev/null 2>&1 || { echo "missing dependency: gh" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "missing dependency: jq" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated — run: gh auth login" >&2; exit 1; }

# --- classifiers -------------------------------------------------------------

is_velnor()   { grep -qiE 'velnor|hetzner-sentry' <<<"$1"; }
is_ghhosted() { grep -qiE '(ubuntu|windows|macos)-[0-9a-z]' <<<"$1"; }

# Print every runs-on value in a workflow file, handling both inline
# (runs-on: X / runs-on: [a, b]) and multi-line list (runs-on:\n  - a\n  - b) forms.
runs_on_values() {
  awk '
    /^[[:space:]]*runs-on:/ {
      line=$0; sub(/^[[:space:]]*runs-on:[[:space:]]*/, "", line)
      gsub(/[][]/, "", line)
      if (line != "") { print line; next }
      while ((getline l) > 0) {
        if (l ~ /^[[:space:]]*-[[:space:]]*/) { sub(/^[[:space:]]*-[[:space:]]*/, "", l); print l }
        else break
      }
    }
  '
}

# --- Goal 1: runner default classification -----------------------------------
# echoes "VERDICT|per-file details"
classify_repo() {
  local repo="$1" branch="$2"
  local files
  files=$(gh api "repos/$repo/contents/.github/workflows?ref=$branch" --jq '.[].name' 2>/dev/null)
  if [[ -z "${files// }" ]]; then echo "NO_CI|-"; return; fi

  local total=0 v=0 g=0 x=0 m=0 details=""
  local f content ro cls fv fg
  while IFS= read -r f; do
    case "$f" in *.yml|*.yaml) ;; *) continue ;; esac
    total=$((total+1))
    content=$(gh api "repos/$repo/contents/.github/workflows/$f?ref=$branch" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
    ro=$(printf '%s\n' "$content" | runs_on_values)
    fv=0; fg=0
    [[ -n "$ro" ]] && is_velnor "$ro"   && fv=1
    [[ -n "$ro" ]] && is_ghhosted "$ro" && fg=1
    if [[ $fv == 1 && $fg == 1 ]]; then cls=MIXED;  m=$((m+1))
    elif [[ $fv == 1 ]];           then cls=VELNOR; v=$((v+1))
    elif [[ $fg == 1 ]];           then cls=GITHUB; g=$((g+1))
    else cls=REVIEW; x=$((x+1)); fi
    details+="$f=$cls "
  done <<<"$files"

  if [[ $total == 0 ]]; then echo "NO_CI|-"; return; fi
  local verdict
  if   [[ $v == $total ]];                              then verdict=VELNOR
  elif [[ $v == 0 && $m == 0 && $g -gt 0 ]];              then verdict=GITHUB
  elif [[ $g == 0 && $m == 0 && $x -gt 0 ]];              then verdict=REVIEW
  else verdict=MIXED; fi
  echo "$verdict|${details% }"
}

# --- Goal 2: main-branch CI status -------------------------------------------
# echoes "STATUS|labels|failed-workflow-names"
main_ci() {
  local repo="$1" branch="$2"
  local latest
  latest=$(gh api "repos/$repo/actions/runs?branch=$branch&per_page=60" \
    --jq '[.workflow_runs[] | select(.event != "pull_request")]
          | group_by(.name)
          | map(sort_by(.created_at) | last | {id, name, status, conclusion})' 2>/dev/null)
  if [[ -z "$latest" || "$latest" == "[]" ]]; then echo "NO_RUNS|-|-"; return; fi

  local running failed st
  running=$(jq -r '[.[] | select(.status != "completed")] | length' <<<"$latest")
  failed=$(jq -r '[.[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral") | .name] | join(", ")' <<<"$latest")
  if   [[ "$running" -gt 0 ]]; then st=RUNNING
  elif [[ -n "$failed" ]];     then st=RED
  else st=GREEN; fi

  local labels="-"
  if [[ $LABELS == 1 ]]; then
    local all="" id l
    while IFS= read -r id; do
      [[ -z "$id" ]] && continue
      l=$(gh api "repos/$repo/actions/runs/$id/jobs?per_page=100" --jq '[.jobs[].labels[]] | unique | join(" ")' 2>/dev/null)
      all="$all $l"
    done < <(jq -r '.[].id' <<<"$latest")
    all=$(tr ' ' '\n' <<<"$all" | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ $//')
    if   [[ -z "${all// }" ]];            then labels="unknown"
    elif is_velnor "$all" && ! is_ghhosted "$all"; then labels="velnor"
    elif is_ghhosted "$all" && ! is_velnor "$all"; then labels="github: $all"
    else labels="mixed: $all"; fi
    labels="${labels:0:80}"
  fi
  echo "$st|$labels|${failed:--}"
}

# --- Goal 2: open PR check status --------------------------------------------
pr_status() {
  local repo="$1"
  local prs
  prs=$(gh pr list -R "$repo" --state open --limit 100 --json number,statusCheckRollup 2>/dev/null)
  if [[ -z "$prs" || "$prs" == "[]" ]]; then echo "-"; return; fi
  jq -r '
    def cls:
      (.statusCheckRollup // []) as $r
      | if ($r | length) == 0 then "none"
        else
          ([$r[] | (.conclusion // .state // "") | ascii_upcase]) as $c
          | ([$r[] | (.status // "") | ascii_upcase]) as $s
          | if ($c | any(. as $x | ["FAILURE","ERROR","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE"] | index($x))) then "fail"
            elif ($s | any(. as $x | ["PENDING","QUEUED","IN_PROGRESS","WAITING","REQUESTED"] | index($x)))
                 or ($c | any(. == "PENDING" or . == "")) then "pending"
            else "ok" end
        end;
    [.[] | {n: .number, c: cls}] as $p
    | ([$p[] | select(.c == "fail")    | "#" + (.n | tostring)]) as $f
    | ([$p[] | select(.c == "pending") | "#" + (.n | tostring)]) as $w
    | "\($p | length) open"
      + (if ($f | length) > 0 then ", FAIL: \($f | join(" "))" else "" end)
      + (if ($w | length) > 0 then ", pending: \($w | join(" "))" else "" end)
      + (if ($f | length) == 0 and ($w | length) == 0 then ", all green" else "" end)
  ' <<<"$prs"
}

# --- main loop ----------------------------------------------------------------

mapfile -t repos < <(grep -vE '^[[:space:]]*(#|$)' "$REPOS_FILE")
[[ -n "$ONLY_REPO" ]] && repos=("$ONLY_REPO")

rows=()
g1=0; g1_applicable=0; g2=0; pr_ok=0; i=0

for repo in "${repos[@]}"; do
  i=$((i+1))
  printf '[%d/%d] %s\n' "$i" "${#repos[@]}" "$repo" >&2

  branch=$(gh api "repos/$repo" --jq '.default_branch' 2>/dev/null)
  if [[ -z "${branch:-}" || "$branch" == "null" ]]; then
    rows+=("| $i | $repo | ⚠️ repo inaccessible | - | - | - |")
    continue
  fi

  rcell="-"; mcell="-"; lcell="-"; pcell="-"

  if [[ $MODE_RUNNERS == 1 ]]; then
    IFS='|' read -r verdict _details <<<"$(classify_repo "$repo" "$branch")"
    case "$verdict" in
      VELNOR) rcell="✅ VELNOR"; g1=$((g1+1)); g1_applicable=$((g1_applicable+1)) ;;
      NO_CI)  rcell="⬜ NO_CI" ;;
      GITHUB) rcell="❌ GITHUB"; g1_applicable=$((g1_applicable+1)) ;;
      MIXED)  rcell="🟡 MIXED";  g1_applicable=$((g1_applicable+1)) ;;
      REVIEW) rcell="🔍 REVIEW"; g1_applicable=$((g1_applicable+1)) ;;
      *)      rcell="⚠️ $verdict" ;;
    esac
  fi

  if [[ $MODE_CI == 1 ]]; then
    IFS='|' read -r st lcell _failed <<<"$(main_ci "$repo" "$branch")"
    case "$st" in
      GREEN)   mcell="✅ GREEN" ;;
      RED)     mcell="❌ RED ($_failed)" ;;
      RUNNING) mcell="🟡 RUNNING" ;;
      NO_RUNS) mcell="⬜ NO_RUNS" ;;
      *)       mcell="⚠️ $st" ;;
    esac
    [[ "$lcell" == "-" && $LABELS == 0 ]] && lcell="(skipped)"
    pcell="$(pr_status "$repo")"

    if [[ "$st" == "GREEN" && ( $LABELS == 0 || "$lcell" == velnor* ) ]]; then g2=$((g2+1)); fi
    if [[ "$pcell" == "-" || "$pcell" == *"all green"* ]]; then pr_ok=$((pr_ok+1)); fi
  fi

  rows+=("| $i | $repo | $rcell | $mcell | $lcell | $pcell |")
done

total=${#repos[@]}

{
  echo "# TRACKER — Velnor CI Green Everywhere"
  echo
  echo "Auto-generated by \`scripts/audit.sh\` at $(date -u '+%Y-%m-%d %H:%M UTC'). Do not hand-edit."
  echo
  echo "## Summary"
  echo
  echo "- Goal 1 — Velnor default runner: **$g1/$g1_applicable** repos with CI ($((total-g1_applicable)) without CI)"
  echo "- Goal 2 — main green on Velnor: **$g2/$total**"
  echo "- Open PRs all green (or none open): **$pr_ok/$total**"
  echo
  echo "Legend: ✅ done · ❌ violates goal · 🟡 partial/in-flight · 🔍 needs manual review (matrix/expression runs-on) · ⬜ no CI / no runs"
  echo
  echo "| # | Repo | G1: runner default | G2: main CI | Main runs on | Open PRs |"
  echo "|---|------|--------------------|-------------|--------------|----------|"
  printf '%s\n' "${rows[@]}"
  echo
} > /tmp/audit-tracker.$$.md

cat /tmp/audit-tracker.$$.md

if [[ $WRITE == 1 ]]; then
  mv /tmp/audit-tracker.$$.md "$TRACKER"
  printf '\nTRACKER.md updated.\n' >&2
else
  rm -f /tmp/audit-tracker.$$.md
fi
