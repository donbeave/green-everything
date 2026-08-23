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

# Classify a raw string as V/G/R, ignoring the generator's matrix KEY name
# velnor_default_runner (a field name, not a runner label — otherwise JSON blobs
# like '{"velnor_default_runner":"macos-26"}' match both label regexes).
label_class() {
  local s="${1//velnor_default_runner/KEY}"
  if   is_velnor "$s" && ! is_ghhosted "$s"; then echo V
  elif is_ghhosted "$s" && ! is_velnor "$s"; then echo G
  else echo R; fi
}

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

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Pick the branch of a runs-on / matrix-axis ternary chain that the workflow's
# DEFAULT resolves to. Normally the fallback after the last '||' (the branch
# for pull_request / schedule / dispatch-default). Exception: lanes workflows
# with no automatic (non-push) triggers — push is the only non-dispatch event
# and routes to the GitHub lane by fleet policy — put the GitHub lane last, so
# the G1 default there is the explicit dispatch-default branch
# (inputs.lanes == 'velnor').
default_branch_of() {
  local s="$1"
  if [[ "$2" == 1 ]]; then
    local seg
    while [[ "$s" == *" || "* ]]; do
      seg="${s%% ||*}"
      if [[ "$seg" == *"inputs.lanes == 'velnor'"* ]]; then
        s="${seg##*&&}"
        break
      fi
      s="${s#* || }"
    done
  fi
  printf '%s' "${s##*||}"
}

# Reduce an already-selected branch to a bare token: strips ${{ }} / quotes.
token_from_expr() {
  local s="$1"
  s="$(trim "$s")"
  s="${s#\$\{\{}"
  s="${s%\}\}}"
  s="$(trim "$s")"
  s="${s%\'}"; s="${s#\'}"; s="${s%\"}"; s="${s#\"}"
  s="${s%,}"
  printf '%s' "$(trim "$s")"
}

# Classify a resolved token: V=velnor default, G=github-hosted default,
# VG=both reachable, R=unresolvable. Resolves matrix.<axis> refs against the
# axis definition in the same file and inputs.<name> refs against the input's
# declared default. Depth-capped to survive pathological references.
classify_token() {
  local tok="$1" content="$2" prefer="${3:-0}" depth="${4:-0}"
  [[ $depth -ge 4 ]] && { echo R; return; }

  if [[ "$tok" == matrix.* ]]; then
    local axis="${tok#matrix.}"; axis="${axis%%.*}"
    local out="" line cls
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      cls=$(classify_token "$(token_from_expr "$(default_branch_of "${line#*"${axis}":}" "$prefer")")" "$content" "$prefer" $((depth+1)))
      out+="$cls"$'\n'
    done < <(printf '%s\n' "$content" | grep -E "(^|[[:space:]{,])${axis}:" 2>/dev/null)
    local uniq
    uniq=$(printf '%s' "$out" | sed '/^$/d' | sort -u | tr -d '\n')
    case "$uniq" in
      V)      echo V ;;
      G)      echo G ;;
      VG|GV)  echo VG ;;
      *)      echo R ;;
    esac
    return
  fi

  if [[ "$tok" == inputs.* ]]; then
    local inp="${tok#inputs.}"; inp="${inp%%.*}"
    local def
    def=$(printf '%s\n' "$content" | awk -v k="$inp" '
      { l[NR]=$0 }
      END {
        for (i=1; i<=NR; i++)
          if (l[i] ~ "^[[:space:]]*" k ":")
            for (j=i+1; j<=i+10 && j<=NR; j++)
              if (l[j] ~ /^[[:space:]]*default:/) {
                sub(/^[[:space:]]*default:[[:space:]]*/, "", l[j]); print l[j]; exit
              }
      }')
    def="$(token_from_expr "$def")"
    label_class "$def"
    return
  fi

  label_class "$tok"
}

# Classify a single runs-on value within a file.
classify_runson_value() {
  local val="$1" content="$2" prefer="${3:-0}"
  if [[ "$val" != *'${{'* && "$val" != *'||'* ]]; then
    label_class "$val"
    return
  fi
  classify_token "$(token_from_expr "$(default_branch_of "$val" "$prefer")")" "$content" "$prefer" 0
}

# Classify one workflow file: where does its runner default resolve?
# A "lanes" workflow (generator-canonical workflow_dispatch input
# velnor|github|both, default velnor) carries github-hosted labels only as the
# push / dispatch-github branch — fleet policy merged_push_occupancy routes
# post-merge push to the GitHub lane by design — so its verdict is where the
# default branch (pull_request / schedule / dispatch-default) lands.
classify_file() {
  local content="$1"
  local has_lanes=0
  if printf '%s\n' "$content" | grep -E -A4 '^[[:space:]]*lanes:' 2>/dev/null | grep -qE '^[[:space:]]*default:[[:space:]]*velnor[[:space:]]*$'; then
    has_lanes=1
  fi
  # pull_request / merge_group triggers present? If not, the only non-dispatch
  # events are push/schedule — writer workflows (renovate, deploy, reuse on
  # main) whose GitHub lane is by-design push occupancy — so the G1 default to
  # check is the dispatch-default branch instead of the last '||' fallback.
  local has_auto=0
  if printf '%s\n' "$content" | awk '
        /^on:/ {inon=1; next}
        inon && /^[^[:space:]#]/ {inon=0}
        inon && /pull_request|merge_group/ {found=1; exit}
        END {exit !found}
      '; then
    has_auto=1
  fi
  local prefer=0
  [[ $has_lanes == 1 && $has_auto == 0 ]] && prefer=1

  local v=0 g=0 m=0 x=0 val cls
  while IFS= read -r val; do
    [[ -z "${val// }" ]] && continue
    cls=$(classify_runson_value "$val" "$content" "$prefer")
    case "$cls" in
      V)  v=$((v+1)) ;;
      G)  g=$((g+1)) ;;
      VG) m=$((m+1)) ;;
      *)  x=$((x+1)) ;;
    esac
  done < <(printf '%s\n' "$content" | runs_on_values)

  if [[ $has_lanes == 1 ]]; then
    # VG (velnor reachable + github push/macos legs) still defaults to velnor
    if   [[ $x -gt 0 ]];       then echo REVIEW
    elif [[ $((v+m)) -gt 0 ]]; then echo VELNOR
    elif [[ $g -gt 0 ]];       then echo GITHUB
    else echo REVIEW; fi
    return
  fi
  if   [[ $v -gt 0 && $g -eq 0 && $m -eq 0 && $x -eq 0 ]]; then echo VELNOR
  elif [[ $g -gt 0 && $v -eq 0 && $m -eq 0 && $x -eq 0 ]]; then echo GITHUB
  elif [[ $x -gt 0 && $v -eq 0 && $g -eq 0 && $m -eq 0 ]]; then echo REVIEW
  else echo MIXED; fi
}

# --- Goal 1: runner default classification -----------------------------------
# echoes "VERDICT|per-file details"
classify_repo() {
  local repo="$1" branch="$2"
  local files
  files=$(gh api "repos/$repo/contents/.github/workflows?ref=$branch" --jq '.[].name' 2>/dev/null)
  if [[ -z "${files// }" ]]; then echo "NO_CI|-"; return; fi

  local total=0 v=0 g=0 x=0 m=0 details=""
  local f content cls
  while IFS= read -r f; do
    case "$f" in *.yml|*.yaml) ;; *) continue ;; esac
    total=$((total+1))
    content=$(gh api "repos/$repo/contents/.github/workflows/$f?ref=$branch" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
    cls=$(classify_file "$content")
    case "$cls" in
      VELNOR) v=$((v+1)) ;;
      GITHUB) g=$((g+1)) ;;
      MIXED)  m=$((m+1)) ;;
      *)      x=$((x+1)) ;;
    esac
    details+="$f=$cls "
  done <<<"$files"

  if [[ $total == 0 ]]; then echo "NO_CI|-"; return; fi
  local verdict
  if   [[ $v == $total ]];                 then verdict=VELNOR
  elif [[ $v == 0 && $m == 0 && $g -gt 0 ]]; then verdict=GITHUB
  elif [[ $g == 0 && $m == 0 && $x -gt 0 ]]; then verdict=REVIEW
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
