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
system, managed with pnpm. Every one of them deploys to Cloudflare on merge to `main` via its own
`.github/workflows/deploy.yml`; the Workers-binding examples (webshop, kv-guestbook, json-api, …)
additionally carry wrangler config and bootstrap workflows. Their shared shape is what makes
"do X to every one" a sensible operation.

Do not assume the list above is complete or fixed — always discover the current set with
`.claude/skills/l-each/scripts/discover-repos.sh` (any `zfb-example-*` git repo next to
zfbex-tweaker).

## The l-* skills

`/l-each <task>` runs the same task across every discovered zfb example site. See
`.claude/skills/l-each/SKILL.md`. In short:

- `/l-each /some-command` → runs that slash command verbatim in each repo.
- `/l-each <natural-language request>` → runs `/x -m -a <request>` in each repo (full
  plan → implement → merge → cleanup automation).

Before running anything, `/l-each` enforces a **preparation safety gate**: every repo must be on a
clean `main`. If a repo has meaningful uncommitted work (a modified page, an untracked source file —
often an edit someone forgot to commit), `/l-each` stops, reports it, and asks before touching
anything. Build noise like `.zfb-build/` is ignored; real work is never bulldozed.

`/l-sync` is the lightweight companion: it only checks out `main` and pulls (`--ff-only`) in every
repo, reporting anything it can't safely touch. It never commits, merges, or force-anything.

`/l-bump-all` is the one full round built on top of both: sync + gate, resolve the
`@takazudo/zfb*` target read-only, prove it on a pilot repo, dispatch
`/x -m -a /dev-bump-zudo-deps` to the rest via `/l-each`, then audit the fleet back to convergence.
Two fleet facts drive its design — the zfb packages are pinned exact and move in lockstep, and
every repo deploys to Cloudflare on merge, so a bad bump ships rather than merely failing CI.

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
