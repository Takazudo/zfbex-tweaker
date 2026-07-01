---
name: l-each
description: >-
  Run one task across every zfb example site (the zfb-example-* siblings of zfbex-tweaker) so it
  doesn't have to be repeated by hand in each one. Use when the user types /l-each, or asks to apply
  a change, fix, dependency bump, or any dev task "to each / across all / for every zfb example
  repo". The argument is either a slash command run verbatim per repo (e.g. /l-each
  /dev-bump-zudo-deps) or a natural-language dev request that defaults to /x -m -a per repo (e.g.
  /l-each footer copyright year is wrong, fix it).
user-invocable: true
disable-model-invocation: true
argument-hint: <slash-command | natural-language dev request>
---

# /l-each — run a task across every zfb example site

zfbex-tweaker is the control repo for a family of zfb example sites that live as siblings:
`../zfb-example-*/`. Each is an independent git repo. `/l-each` applies the SAME task to all of them,
after first making sure each one is safe to touch.

The task to run is: **$ARGUMENTS**

## Routing: what "the task" means

Trim `$ARGUMENTS`, then:

- **Starts with `/`** → it is a slash command. Run it verbatim in each repo (e.g.
  `/dev-bump-zudo-deps`). That command governs its own commit/push behavior.
- **Anything else** → it is a natural-language dev request. Run **`/x -m -a <request>`** in each
  repo. `/x -m -a` plans, implements, reviews, merges to main, and cleans up autonomously — the full
  hands-off chain, once per repo.

If the user named specific repos in the invocation ("…for blog and webshop only"), operate on just
those; otherwise operate on every discovered repo.

## Phase 1 — Discover the repos

```bash
.claude/skills/l-each/scripts/discover-repos.sh
```

Prints one absolute repo path per line (every `zfb-example-*` git repo next to zfbex-tweaker). New
repos are picked up automatically just by being cloned as a sibling. Work from this list.

## Phase 2 — Preparation safety gate (before ANY task runs)

Each task — especially `/x -m -a`, which merges to main on its own — must never run on top of
uncommitted work. Assess every repo first, read-only:

```bash
.claude/skills/l-each/scripts/prep-check.sh <repo-path>
```

It prints `VERDICT: CLEAN` (exit 0) or `VERDICT: DIRTY` (exit 3) plus details, and never mutates the
repo.

**Meaningful vs. noise** — DIRTY means real uncommitted work: modified or staged tracked files, or
untracked source files (e.g. a half-finished page or component). Build/editor artifacts like
`.zfb-build/`, `dist/`, or `.wrangler/` are filtered out as noise, even in a repo that forgot to
gitignore them. When unsure, the script errs toward meaningful — better to ask than to bulldoze.

Then:

- **Any DIRTY repo** → STOP. Do not run the task anywhere yet. Show the user a consolidated report of
  every problem repo with its details (branch + what is uncommitted), because a DIRTY repo often
  means an edit that was never committed — exactly the thing they would want to know. Ask whether to
  (a) proceed on the CLEAN repos only, or (b) abort so they can resolve it first. Wait for the
  answer.
- **CLEAN repos** → if not already on `main`, switch them:
  ```bash
  git -C <repo-path> checkout main
  ```

  Checking out main is what makes `/x` branch from and merge back into main. Do not pull or fetch
  unless asked. If `prep-check` reported `UNPUSHED_COMMITS`, mention it — it is not a blocker.

## Phase 3 — Run the task in each ready repo

Dispatch one subagent per ready repo (via the Agent tool), all in a single batch so they run
concurrently. Each subagent prompt must:

- Pin the work to that repo: every shell command runs with the repo as its working directory (start
  with `cd <repo-path> &&`, or use `git -C <repo-path>`); all file paths stay under it.
- Run the task — the verbatim slash command, or `/x -m -a <request>` — via the Skill tool.
- Report back tersely: what changed, branch / PR / merge / CI outcome, or the failure reason.

`/l-each` itself does not commit, push, or merge — the task (`/x -m -a` or the passed command) owns
that. Caveat: a target repo's own project skills are not auto-loaded in the subagent (it is a
sibling, not the session root); `/x` and the finalize flow rely on global skills, so this is fine in
practice.

If the user asked to watch merges one at a time, run the subagents sequentially instead of batched.

## Phase 4 — Report

Summarize per repo in one table: outcome (done / failed / skipped-dirty), what changed, and
PR / merge / CI status. Make skipped DIRTY repos and any failures impossible to miss.
