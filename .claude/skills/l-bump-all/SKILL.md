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

**One gate, at the top.** This skill carries `disable-model-invocation: true`; `/l-sync` and
`/l-each` deliberately do not. The human decision for the whole round happens once — when the user
types `/l-bump-all` — and the orchestration below is then free to chain them. Do not re-add the flag
to the sub-skills: it makes Phase 1 and Phase 3 unrunnable, because the Skill tool refuses a
model-blocked skill and forbids reproducing its workflow by other means.

## What makes this fleet different — read before adapting anything

- **The zfb packages are pinned exact and move in lockstep — and upstream enforces it.** Every
  example carries `@takazudo/zfb` and `@takazudo/zfb-runtime`, and the Cloudflare-binding ones also
  carry `@takazudo/zfb-adapter-cloudflare` — all on the *same* version. Half of that is enforced
  upstream and half is ours to hold: `@takazudo/zfb-runtime` declares
  `peerDependencies: { "@takazudo/zfb": "<exact version>" }`, so moving one of those two alone simply
  will not resolve; `@takazudo/zfb-adapter-cloudflare` declares **no** peerDependencies, so nothing
  stops a worker from leaving it behind — that one is convention, and the Phase 4 lockstep check is
  what catches it. A round that leaves them mismatched inside a repo, or leaves the fleet straddling
  two zfb generations, has not converged.
- **An empty JS diff does not mean an inert bump.** The published JS for a zfb release is often
  `package.json`-only; the actual fix ships in the native binaries that `@takazudo/zfb` pins exactly
  through `optionalDependencies` (`@takazudo/zfb-{darwin,linux,win32}-*`). Never conclude from
  `npm diff` alone that a bump changed nothing.
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

**Dispatch in batches, not all at once — nine concurrent workers exhaust the session limit.** A
measured round: the pilot plus nine parallel `/x -m -a` workers, each spawning its own review
sub-agent, hit `You've hit your session limit`, and most workers reported failure mid-flight at
nearly the same instant — at different stages, some after merging and verifying, some holding an
open PR, some mid-checklist. The fleet was left in a mixed state that no single report described.
Prefer two or three batches of three or four. Budget for the review sub-agent each worker spawns; it
roughly doubles the cost per repo.

**A worker that reported failure is not necessarily dead — re-check ground truth immediately before
you act on its repo.** In the measured round at least one worker continued past its own failure
notification and completed its full task — merge, deploy verification, cleanup — *after* the
orchestrator had already surveyed the fleet and recorded its PR as unfinished. Acting on a stale
survey risks colliding with a live worker (a duplicate merge attempt returned "already merged"
rather than doing damage, but that was luck, not design). Re-read the repo's state in the same step
as the action you take on it.

**Recovering is straightforward, so do not re-dispatch blind.** Worker reports may be lost, but the
fleet state is fully recoverable from ground truth, and that is the authority regardless — including
over a worker's own account of what it did: per repo, `git rev-parse origin/main` plus the version
in `git show origin/main:package.json`, `gh pr list --state open`, and the push-event Deploy run for
the merge SHA. Reconstruct from those, finish whatever is genuinely unfinished, then run Phase 4 as
normal — Phase 4 is a state audit and does not care who performed the work.

If the pilot needed a source change, hand every worker the pilot's diff and its reasoning — as
**evidence, not a patch to apply blind**. Each repo still runs its own resolver, install, and
verification; page and component shapes differ per example, and a Workers-binding repo is not a
static one.

No worker may relax the pin style: exact stays exact, and every `@takazudo/zfb*` package in a repo
moves to the same version together.

**Every example carries its own zfb-update checklist, and workers will not see it.** Each repo has
`.claude/skills/l-handle-zfb-update/SKILL.md` — a verification protocol its author wrote for exactly
this operation (rebuild from clean, confirm the emitted CSS hash and linkage, global tokens vs
scoped module rules, zero Tailwind leakage, zero stray JS/`<script>` output, no stranded temp files,
README class names still matching emitted output). A dispatched worker does **not** auto-load it,
because the target repo is a sibling of the session root rather than the root itself. Tell every
worker to read and execute it by hand before merging, and to treat a failure as a blocker. It is a
stronger gate than `pnpm build` alone: it is what distinguishes "the build exited 0" from "the site
still renders what it used to.

**Expect exactly one changed output hash on any adapter repo, and do not call it a regression.**
Comparing the emitted tree across a patch bump, a static repo is byte-identical, but a repo whose
build runs the Cloudflare adapter differs in `_zfb_inner.mjs` alone: esbuild inlines provenance
comments carrying the pnpm store paths, which embed the version string
(`…/.pnpm/@takazudo+zfb@<old>/…` → `@<new>`). Zero code difference — measured identical byte length
when the two version strings are the same length. `.assetsignore`, `404.html`, `__zfb/routes.json`,
`_worker.js` and the hashed CSS stay identical. So: a changed `_zfb_inner.mjs` alone is noise, a
changed `_worker.js` is a real signal worth stopping for.

Two more build outputs that look alarming and are not: `0 pages built` is correct for an SSR recipe
whose routes all carry `"prerender": false`, and a missing `dist/index.html` is correct when
`pages/index.tsx` sets `prerender = false` and the Worker serves it at request time.

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
   that actually matters here — that the **Deploy run for the merge SHA succeeded**. A green job
   conclusion is NOT sufficient evidence that anything shipped: `deploy.yml` has a
   `Preflight — is Cloudflare configured?` step that sets `ready=false` when `CLOUDFLARE_API_TOKEN`
   is unset, and the credentialed steps are then **skipped while the job still succeeds**. Always
   read the step list, not the conclusion:

   ```bash
   gh run view <id> --repo <owner/repo> --json headSha,conclusion,jobs \
     --jq '.headSha, .conclusion, (.jobs[].steps[]
           | select(.name | test("(?i)deploy|smoke"))
           | "\(.conclusion)\t\(.name)")'
   ```

   Every deploy/smoke step it prints must read `success`. A `skipped` among them means nothing
   shipped, whatever the job conclusion says.

   **Match by pattern, never by literal step name — the names differ in every repo.** Observed
   variants include `Smoke test the live site`, `Smoke test the custom domain`,
   `Smoke test — is the custom domain live?`, `Smoke test — is the live gate actually gating?`,
   `Smoke-test the custom domain`, and `E2E smoke`. Two repos are structurally different and need
   a look rather than a pattern:

   - `zfb-example-img-gallery` has `Detect Cloudflare deployment readiness`, a **`Report deferred
     Cloudflare deployment`** step, and separate `Smoke-test PR preview` / `Smoke-test the custom
     domain` steps. A run that reports a *deferred* deployment has not shipped — do not read it as
     success.
   - `zfb-example-webshop` has **no preflight step at all**, just `Deploy production Worker` and
     `Smoke-test the custom domain`, so the skipped-but-green trap does not apply there the way it
     does elsewhere.

   The smoke steps are also not uniform in what they prove. Several are real functional exercises,
   not page-200 checks — kv-guestbook's asserts `GET /` renders an entry list or the empty-guestbook
   message and that `GET /api/entries` returns an array (a text/plain 503 is what a missing KV
   binding yields), and password-gate's asserts the gate actually gates. Treat a green smoke step on
   a bindings repo as the real evidence that bindings survived the bump.

   Diagnose a red Deploy by which step failed before blaming the bump: `Deploy` failing points at
   wrangler or credentials — triage against `docs/cloudflare-shared-token-and-env-setup.md` Part 4;
   `Smoke test the live site` failing points at domain reachability, because that step runs with
   `SMOKE_REQUIRE_LIVE=1`, which turns "custom domain not serving yet" into a hard failure even
   when the bump is perfectly good.
5. Confirm no workflow leftovers: no stray branch, open PR, or `worktrees/` directory in any repo.
   Expect workers to have verified their own cleanup **deterministically rather than through
   `/cleanup-resources`**: that skill audits via a subagent, and a subagent spawned beneath a worker
   starts in the control repo rather than the worker's repo (same hazard as the review step). With
   zero resources left to audit the direct checks are equivalent and carry no cross-repo risk — but
   the orchestrator still owns a real fleet-wide sweep here, because no worker can see its peers.
6. If any command was blocked during the round, run `/permission-review` — ten autonomous
   `/x` workflows generate denials that are worth triaging in one pass, and a step skipped because
   of a block must appear in the report rather than read as a step that succeeded.

Report one consolidated table: repo, current → target (or no-op), PR, merge, post-merge Deploy, and
cleanup. Make any skipped repo, failed deploy, version mismatch, remaining branch, or unresolved
cross-fleet finding impossible to miss.
