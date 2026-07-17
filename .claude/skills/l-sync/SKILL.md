---
name: l-sync
description: >-
  Refresh every zfb example site to a clean, up-to-date main: checkout main and git pull
  (fast-forward only) for each. Never touches a repo that has meaningful uncommitted changes --
  reports it instead. Use when the user types /l-sync, or asks to "refresh/sync/update each zfb
  example repo" or "pull latest for all zfb example repos".
user-invocable: true
disable-model-invocation: true
argument-hint: (optional) repo names to limit to, e.g. blog webshop
---

# /l-sync — refresh every zfb example site to a clean, up-to-date main

Lightweight companion to `/l-each`: no dev task is run, no commits/merges happen. This just
checks out `main` and pulls (fast-forward only) in every zfb example site, and reports any repo
that can't be safely touched.

If the user named specific repos in `$ARGUMENTS`, operate on just those; otherwise operate on
every discovered repo.

## Phase 1 — Discover the repos

```bash
.claude/skills/l-each/scripts/discover-repos.sh
```

Reuses `/l-each`'s discovery script (every `zfb-example-*` git repo next to zfbex-tweaker). New
repos are picked up automatically just by being cloned as a sibling.

## Phase 2 — Sync each repo

For each discovered repo, run directly (sequentially — these are cheap git operations, no need
for subagents):

```bash
.claude/skills/l-sync/scripts/sync-repo.sh <repo-path>
```

Per repo, the script:

- If the repo has meaningful uncommitted changes (modified/staged tracked files, or untracked
  source files — build noise like `.zfb-build/`, `dist/`, or `.wrangler/` is filtered out): does
  **NOT** touch it. Prints `VERDICT: DIRTY` with details and exits 3.
- Otherwise: `git checkout main`, then `git pull --ff-only`, and prints whether it updated or was
  already up to date. Never force-pulls or rebases — a diverged main is reported as
  `PULL_FAILED`, not clobbered.
- After a successful pull, also checks whether local `main` is still ahead of `origin/main` (real
  unpushed local commits — a `--ff-only` pull says nothing about these, so "up to date" alone does
  NOT mean "nothing to push"). Prints `AHEAD_OF_ORIGIN: N` when true.

`/l-sync` itself never commits, pushes, merges, or force-anything.

## Phase 3 — Report

One consolidated table: repo, branch, outcome (`pulled <old>..<new>` / `up to date` / `DIRTY` /
`PULL_FAILED` / `CHECKOUT_FAILED`), plus an unpushed-commits column. Make DIRTY repos,
`AHEAD_OF_ORIGIN` repos, and any failures impossible to miss — both usually mean real work
(uncommitted or unpushed) that the user forgot about, which is exactly what they'd want flagged.
