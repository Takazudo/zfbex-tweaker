# zfbex-tweaker

Control repo for tweaking the family of **zfb example sites** in bulk.

This repo holds no site of its own. Its job is to apply a single change — a dependency bump, a shared
fix, a convention update — across every zfb example site at once, instead of repeating the same edit
by hand in each one. New example sites are added over time; the tooling here discovers them
automatically.

## The zfb example sites

Each example is an independent git repository that lives as a **sibling** of zfbex-tweaker (same
parent directory), named `zfb-example-<topic>`:

```
repos/zfb-ex/
├── zfbex-tweaker/                  ← this repo (the control repo)
├── zfb-example-blog/
├── zfb-example-corporate-website/
└── zfb-example-webshop/            ← …and more added over time
```

They are all built the same way: [zfb](https://github.com/Takazudo/zudo-front-builder)
(`@takazudo/zfb`, "zudo-front-builder") — a Rust-orchestrated static site builder with
server-rendered Preact pages and selective client-side hydration ("islands"), a Tailwind v4 design
system, managed with pnpm. `zfb-example-webshop` additionally deploys to Cloudflare (wrangler). Their
shared shape is what makes "do X to every one" a sensible operation.

Do not assume the list above is complete or fixed — always discover the current set with
`.claude/skills/l-each/scripts/discover-repos.sh` (any `zfb-example-*` git repo next to
zfbex-tweaker).

## /l-each — the one skill that matters here

`/l-each <task>` runs the same task across every discovered zfb example site. See
`.claude/skills/l-each/SKILL.md`. In short:

- `/l-each /some-command` → runs that slash command verbatim in each repo.
- `/l-each <natural-language request>` → runs `/x -m -a <request>` in each repo (full
  plan → implement → merge → cleanup automation).

Before running anything, `/l-each` enforces a **preparation safety gate**: every repo must be on a
clean `main`. If a repo has meaningful uncommitted work (a modified page, an untracked source file —
often an edit someone forgot to commit), `/l-each` stops, reports it, and asks before touching
anything. Build noise like `.zfb-build/` is ignored; real work is never bulldozed.

## Conventions

- Project-scope skills in this family use an **`l-` prefix** (`l-each`, and any `l-*` helper added
  later). Personal/global tooling skills use other prefixes (`dev-*`, `gh-*`, …).
- File names: kebab-case.
- Scripts that operate across repos self-locate relative to zfbex-tweaker and act on siblings — they
  take no hardcoded absolute paths, so the tooling keeps working when the repo set changes.

## Safety

- `/l-each` never commits, pushes, or merges on its own — the dispatched task owns that. The gate
  exists so an autonomous, merging task (`/x -m -a`) is never unleashed on top of uncommitted work.
- `rm -rf`: relative paths only (`./path`), never absolute.
- No force push, no `--amend` unless explicitly permitted.
