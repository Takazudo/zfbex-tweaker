#!/usr/bin/env bash
# Refresh ONE zfb example site: checkout main + git pull (fast-forward only).
# If the repo has meaningful uncommitted changes, do NOT touch it -- report DIRTY instead.
# Never force-anything: pull is --ff-only, so a diverged main is reported, not clobbered.
#
# Usage: sync-repo.sh <repo-path>
# Exit:  0 = synced (pulled or already up to date)
#        3 = DIRTY -- skipped, must be reported
#        4 = pull failed (e.g. diverged / no fast-forward)
#        5 = checkout main failed
#        2 = bad argument / not a git repo
set -euo pipefail

repo="${1:-}"
[ -n "$repo" ] || { echo "usage: sync-repo.sh <repo-path>" >&2; exit 2; }
[ -d "$repo/.git" ] || { echo "not a git repo: $repo" >&2; exit 2; }

# Same noise filter as l-each/scripts/prep-check.sh -- zfb's generated outputs are never
# real work, even when they surface as untracked: .zfb-build/ (build cache), .zfb/ (work
# dir), dist/ (emitted site), .wrangler/ (Cloudflare local state), .zfb-bin/ (fetched
# binaries), and zfb-tailwind-entry-*.css (a temp file zfb can strand on abnormal
# termination -- Takazudo/zudo-front-builder#821). Anything NOT matched here is treated as
# meaningful (fail-safe: better to report than to touch a repo with real uncommitted work).
noise_re='^(\.zfb-build/?|\.zfb/?|dist/?|\.wrangler/?|\.zfb-bin/?|zfb-tailwind-entry-.*\.css|\.DS_Store|Thumbs\.db)$'

branch_before="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '(detached)')"

tracked=()
untracked=()
while IFS= read -r line; do
  [ -n "$line" ] || continue
  code="${line:0:2}"
  path="${line:3}"
  if [ "$code" = "??" ]; then
    if [[ "$path" =~ $noise_re ]]; then
      :
    else
      untracked+=("$path")
    fi
  else
    tracked+=("$code $path")
  fi
# --untracked-files=normal is explicit so the gate never depends on a repo/global
# status.showUntrackedFiles config -- with =no, untracked half-finished work would be
# silently omitted and a DIRTY repo would read as CLEAN. "normal" (not "all") keeps
# untracked directories collapsed to one entry so the noise_re above still matches them.
done < <(git -C "$repo" status --porcelain=v1 --untracked-files=normal)

echo "REPO: $repo"
echo "BRANCH_BEFORE: $branch_before"

if [ "${#tracked[@]}" -gt 0 ] || [ "${#untracked[@]}" -gt 0 ]; then
  echo "VERDICT: DIRTY"
  for t in "${tracked[@]}"; do echo "  tracked-change: $t"; done
  for u in "${untracked[@]}"; do echo "  untracked: $u"; done
  exit 3
fi

if ! checkout_output="$(git -C "$repo" checkout main 2>&1)"; then
  echo "VERDICT: CHECKOUT_FAILED"
  echo "CHECKOUT_OUTPUT: $checkout_output"
  exit 5
fi

before_sha="$(git -C "$repo" rev-parse HEAD)"
if ! pull_output="$(git -C "$repo" pull --ff-only 2>&1)"; then
  echo "VERDICT: PULL_FAILED"
  echo "PULL_OUTPUT: $pull_output"
  exit 4
fi
after_sha="$(git -C "$repo" rev-parse HEAD)"

echo "VERDICT: CLEAN"
if [ "$before_sha" = "$after_sha" ]; then
  echo "PULL_RESULT: up to date ($after_sha)"
else
  echo "PULL_RESULT: updated $before_sha -> $after_sha"
fi

# --ff-only pull only fast-forwards local to remote -- it says nothing about local
# commits remote doesn't have yet. Check explicitly so a forgotten push (the exact
# problem this skill exists to catch) doesn't slip through as a false "up to date".
ahead="$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
[ "$ahead" != "0" ] && echo "AHEAD_OF_ORIGIN: $ahead (unpushed commits)"

exit 0
