---
name: l-bump-all
description: >-
  Run a complete @takazudo/zfb dependency update across every zfb example site: sync clean mains,
  resolve the target read-only, prove the bump on one pilot repo, dispatch the autonomous
  per-repo bump/PR/merge workflow to the rest, propagate cross-fleet findings, and finish with
  resolver, lockstep-pin, post-merge Cloudflare deploy, and cleanup audits. Use when the user
  explicitly types /l-bump-all or asks for the full hands-off zfb dependency bump across the
  example fleet.
user-invocable: true
disable-model-invocation: true
argument-hint: (optional) repo names to limit to, e.g. blog webshop
---

# /l-bump-all — update the whole zfb example fleet

Run one end-to-end first-party dependency round across every repo discovered by `/l-each`. This
skill owns orchestration; `/l-sync`, `/l-each`, `/x`, and `/dev-bump-zudo-deps` own their
established safety and implementation details.

The per-repo task is exactly:

```text
/x -m -a /dev-bump-zudo-deps .
```

`-a` keeps each workflow autonomous and `-m` requires it to merge, watch post-merge CI, and clean
up. Do not silently weaken either flag.

If the user named specific repos in `$ARGUMENTS`, operate on just those; otherwise operate on every
discovered repo.

## What makes this fleet different — read before adapting anything

- **The zfb packages are pinned exact and move in lockstep.** Every example carries
  `@takazudo/zfb` and `@takazudo/zfb-runtime`, and the Cloudflare-binding ones also carry
  `@takazudo/zfb-adapter-cloudflare` — all on the *same* version. A round that leaves those
  mismatched inside a repo, or leaves the fleet straddling two zfb generations, has not converged.
- **Every repo deploys to Cloudflare on merge to `main`** (`.github/workflows/deploy.yml`). A bad
  bump does not merely redden a check — it ships to a live site. "Post-merge CI" here means the
  Deploy run for the merge SHA.
- **There is no vendored scaffold.** No `ZUDO_DEPS_PINS.md`, no `.template-drift-allowlist`. The
  change surface is `package.json` + `pnpm-lock.yaml` plus whatever the upstream release forces in
  source. Do not invent a reconciliation phase — but do read the upstream changelog.

## Phase 1 — sync and gate the fleet

Invoke `/l-sync` (with the user's repo filter, if any). It discovers the fleet dynamically and
checks out / pulls clean `main` with `--ff-only`.

Stop before dispatching any bump if `/l-sync` reports `DIRTY`, `PULL_FAILED`, `CHECKOUT_FAILED`, or
`AHEAD_OF_ORIGIN`. Report the complete fleet result and let the user resolve real work; a full-fleet
autonomous merge round must not begin from partial readiness.

`AHEAD_OF_ORIGIN` is a blocker here even though `/l-sync` treats it as informational — unpushed
local commits on `main` are real work that an autonomous merging round will build on top of and can
bury.

## Phase 2 — resolve, then prove the bump on one pilot

Before mutating anything, run the `/dev-bump-zudo-deps` resolver read-only from each repo root:

```bash
node "$HOME/.claude/skills/dev-bump-zudo-deps/scripts/resolve-bumps.mjs"
```

No `--write`. The resolver is authoritative about today's registry targets — never hand-compute
version math. Record current → target per repo, then:

- **Everything already up to date** → there is nothing to dispatch. Say so and stop. Never
  manufacture manifest or lockfile churn for a genuine resolver no-op.
- **A repo is already on the target while others are not** → it is the reference candidate. Find its
  most recent **relevant dependency PR** (not merely the newest PR overall); read the body, changed
  files, PR checks, Deploy result, and focused diff; extract reusable impact notes for the other
  workers.
- **Nobody is on the target** (the usual case — the fleet moves in lockstep) → **create the evidence
  with a pilot.** Run the per-repo task in exactly one repo first, preferring the smallest
  Cloudflare surface (`zfb-example-blog` or `zfb-example-corporate-website` — static, no bindings).
  Dispatch the rest only once the pilot's PR checks, merge, and post-merge Deploy are all green.

Either way, read the upstream release notes for the version range before the wave
(`Takazudo/zudo-front-builder`; `/dev-read-gh-public-repo`). A patch bump that touches no source
surface needs no more than that. A minor/major — or a pilot that needed source edits — means the
wave workers must be told what to expect.

Skip the pilot only if the user asks for a single wave.

## Phase 3 — dispatch the wave

```text
Skill tool: skill="l-each" args="/x -m -a /dev-bump-zudo-deps ."
```

Let `/l-each` run its fleet-wide preparation gate before it starts any worker. Each ready repo then
runs the single-topic `/x-as-pr` path: fresh branch, resolver and upstream-impact assessment,
write + install, the repo's strongest checks (`pnpm typecheck` / `zfb check`, `pnpm build`), review,
PR, merge, post-merge Deploy, and cleanup.

If the pilot needed a source change, hand every worker the pilot's diff and its reasoning — as
**evidence, not a patch to apply blind**. Each repo still runs its own resolver, install, and
verification; page and component shapes differ per example, and a Workers-binding repo is not a
static one.

No worker may relax the pin style: exact stays exact, and every `@takazudo/zfb*` package in a repo
moves to the same version together.

## Propagate findings across the whole round

A defect exposed in one repo may invalidate repos that already passed. When a worker finds a
first-party regression or a stronger guard:

1. Confirm it belongs upstream and invoke `/dev-upstream-report` once, after checking duplicates.
2. Give the evidence and minimal repro to every still-running repo worker when the harness permits.
3. Audit repos that already merged and run focused follow-up PRs where the finding applies —
   including a re-check of their live deploy, since a merged bad bump is already serving.
4. Compare the resulting variants before standardizing; adopt the strongest tested version, not
   merely the first one written.

Any local workaround for an upstream zfb defect must be linked to its upstream issue, covered by a
focused regression test, and recorded in the section below.

### Known divergences to reassess, not preserve forever

None recorded.

When a round has to work around an upstream zfb defect, add it here with its upstream issue and the
discriminator that proves the workaround is still needed. On every later bump, inspect the new
upstream behavior instead of trusting version numbers: still broken → preserve the tested local
divergence; fixed → deliberately remove the workaround, its test scaffolding, and this entry.

## Phase 4 — prove the fleet converged

Do not stop at "all PRs merged." Finish with all of these:

1. Invoke `/l-sync` again so every checkout lands on clean, current `main`.
2. Rerun the resolver in every repo. Every row must be up to date, with zero pending bumps and zero
   errors. Do not hard-code a package count — repos carry two or three `@takazudo/zfb*` packages
   depending on whether they use the Cloudflare adapter.
3. Prove the lockstep invariant, from the zfbex-tweaker root:

   ```bash
   for r in $(.claude/skills/l-each/scripts/discover-repos.sh); do
     printf '%-32s %s\n' "$(basename "$r")" "$(node -e 'const p=require(process.argv[1]);const a={...p.dependencies,...p.devDependencies};console.log(Object.entries(a).filter(([k])=>k.startsWith("@takazudo/")).map(([k,v])=>k.replace("@takazudo/","")+"@"+v).sort().join(" "))' "$r/package.json")"
   done
   ```

   Every entry on every line must show the same version. A single stray version is a failed round,
   not a rounding error.
4. Confirm each repo is clean on `main`, matches `origin/main`, had green PR checks, and — the one
   that actually matters here — that the **Deploy run for the merge SHA succeeded**
   (`gh run list --workflow deploy.yml -L 3`, then `gh run view <id>`). Before concluding a failed
   deploy means a bad bump, triage it against `docs/cloudflare-shared-token-and-env-setup.md`
   Part 4: a missing or expired secret fails identically to a broken build.
5. Confirm no workflow leftovers: no stray branch, open PR, or `worktrees/` directory in any repo.
6. If any command was blocked during the round, run `/permission-review` — ten autonomous
   `/x` workflows generate denials that are worth triaging in one pass, and a step skipped because
   of a block must appear in the report rather than read as a step that succeeded.

Report one consolidated table: repo, current → target (or no-op), PR, merge, post-merge Deploy, and
cleanup. Make any skipped repo, failed deploy, version mismatch, remaining branch, or unresolved
cross-fleet finding impossible to miss.
