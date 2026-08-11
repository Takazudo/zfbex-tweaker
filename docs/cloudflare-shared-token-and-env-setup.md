# Cloudflare shared token + per-repo env setup

Setup guide for deploying the whole **zfb-example** family from GitHub Actions
using **one shared Cloudflare API token**. All repos deploy to the **same
Cloudflare account**, so a single account-scoped token works everywhere; each
repo just needs the same two GitHub Actions secrets.

The family is 9 repos:

| Repo | Deploy target |
| --- | --- |
| [zfb-example-blog](https://github.com/Takazudo/zfb-example-blog) | **Workers** (static assets) |
| [zfb-example-corporate-website](https://github.com/Takazudo/zfb-example-corporate-website) | **Workers** (static assets) |
| [zfb-example-webshop](https://github.com/Takazudo/zfb-example-webshop) | Cloudflare **Workers** (static assets) + **D1** |
| [zfb-example-ai-summarizer](https://github.com/Takazudo/zfb-example-ai-summarizer) | **Workers** (static assets) + Workers AI |
| [zfb-example-json-api](https://github.com/Takazudo/zfb-example-json-api) | **Workers** (static assets) |
| [zfb-example-kv-guestbook](https://github.com/Takazudo/zfb-example-kv-guestbook) | **Workers** (static assets) + KV |
| [zfb-example-password-gate](https://github.com/Takazudo/zfb-example-password-gate) | **Workers** (static assets, gate) |
| [zfb-example-reverse-proxy](https://github.com/Takazudo/zfb-example-reverse-proxy) | **Workers** (static assets) |
| [zfb-example-workers-cache](https://github.com/Takazudo/zfb-example-workers-cache) | **Workers** (static assets) + Cache |

> **All 9 repos deploy to Workers Static Assets and are live on custom
> domains** (see Part 4). blog and corporate-website were migrated off
> Cloudflare Pages; kv-guestbook was the last to go live once its KV namespace
> was provisioned.

---

## Part 1 — Create the shared API token

Cloudflare dashboard → **My Profile → API Tokens → Create Token → Create Custom
Token**. Because one token covers Pages, Workers, KV, Workers AI, and D1 across
the account, it needs the union of every repo's permissions:

| Type | Permission | Access | Why |
| --- | --- | --- | --- |
| Account | **Workers Scripts** | Edit | every repo (`wrangler deploy`) |
| Zone | **Workers Routes** | Edit | every custom domain (`custom_domain = true`) |
| Zone | **DNS** | Edit | Cloudflare creates/manages each custom domain's DNS record + cert |
| Account | **Workers Scripts** | Edit | webshop + all 6 Workers repos (`wrangler deploy`) |
| Account | **Workers KV Storage** | Edit | kv-guestbook (create namespace + bind) |
| Account | **Workers AI** | Read | ai-summarizer (`AI` binding) |
| Account | **D1** | Edit | webshop (`wrangler d1 migrations apply`) |
| Account | **Account Settings** | Read | wrangler resolves account metadata |

- **Account Resources**: Include → *your account*.
- **Zone Resources**: Include → `takazudomodular.com` (or All zones). This is
  **required** — every site is served on a `*.takazudomodular.com` custom
  domain. Without both Zone permissions above, `wrangler deploy` fails when it
  tries to create the route.
- **Client IP / TTL**: leave default.

> **Blast-radius note.** One broad token that can Edit Pages + Workers + KV + D1
> across the account is convenient but powerful — anyone who can read any repo's
> Actions logs cannot see it (secrets are masked), but treat it as sensitive and
> rotate it if a repo's access changes. If you'd rather minimize scope, mint a
> narrower token per group instead (Pages-only for the 3 Pages repos;
> Workers+KV+AI for the 6 Workers repos) — the per-repo "token perms" column in
> Part 3 shows the minimum each needs.

Copy the token value once (Cloudflare shows it only at creation). You also need
your **Account ID** (dashboard → any domain → right sidebar, or
`wrangler whoami`).

---

## Part 2 — Set the two GitHub secrets in every repo

GitHub **personal-account** repos have no shared/org secret store, so the same
values must be added to each repo's **Settings → Secrets and variables →
Actions**:

| Secret | Value |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | the shared token from Part 1 |
| `CLOUDFLARE_ACCOUNT_ID` | your Cloudflare account id |

Fastest path — set both across all 9 repos with `gh` (run with **your own**
values; nothing is stored here):

```bash
export CF_TOKEN='paste-shared-token'
export CF_ACCOUNT='paste-account-id'

for r in blog corporate-website webshop \
         ai-summarizer json-api kv-guestbook \
         password-gate reverse-proxy workers-cache; do
  gh secret set CLOUDFLARE_API_TOKEN  --repo "Takazudo/zfb-example-$r" --body "$CF_TOKEN"
  gh secret set CLOUDFLARE_ACCOUNT_ID --repo "Takazudo/zfb-example-$r" --body "$CF_ACCOUNT"
done
```

> The 3 Pages repos already hold an older token — this overwrites them with the
> shared one, which is fine as long as it carries **Pages · Edit** (it does).

Once the secrets exist, the next push to `main` (or re-run the latest deploy
workflow) activates the deploy job.

---

## Part 3 — Per-repo extra setup

The two GitHub secrets above are all most repos need. A few also need a
provisioned resource (whose id is committed to the config) and/or a **Worker
secret**, which is stored on Cloudflare via `wrangler secret put` — **not** a
GitHub secret.

| Repo | Provision (commit the id) | Worker secret(s) | Min token perms |
| --- | --- | --- | --- |
| blog | — | — | Workers Scripts: Edit, Zone Workers Routes + DNS: Edit |
| corporate-website | — | — | Workers Scripts: Edit, Zone Workers Routes + DNS: Edit |
| webshop | D1 `webshop` + `webshop-preview` (ids already committed; re-provision via its `d1-bootstrap.yml`) | — | Workers Scripts: Edit, D1: Edit |
| ai-summarizer | — (Workers AI is an account feature, no id) | — | Workers Scripts: Edit, Workers AI: Read |
| json-api | — | — | Workers Scripts: Edit |
| kv-guestbook | KV namespace ✅ provisioned, id committed | `ADMIN_TOKEN` ✅ set | Workers Scripts: Edit, KV: Edit |
| password-gate | — | `SITE_PASSWORD` (optional; has a dev fallback) | Workers Scripts: Edit |
| reverse-proxy | — (`PROXY_ORIGIN` is a public `[vars]` value) | — | Workers Scripts: Edit |
| workers-cache | — | `PURGE_TOKEN` (optional) | Workers Scripts: Edit |

### kv-guestbook — KV + admin token (both done)

Provisioned and live; this section is kept for re-provisioning.

The repo carries a **`KV bootstrap (one-time)`** workflow that runs
`wrangler kv namespace create` in CI, where the `CLOUDFLARE_*` secrets actually
live — preferable to running it locally, which needs your own Cloudflare
credentials:

```bash
gh workflow run kv-bootstrap.yml --repo Takazudo/zfb-example-kv-guestbook --ref main
gh run download <run-id> --repo Takazudo/zfb-example-kv-guestbook -n kv-id
# → paste the id into wrangler.toml's [[kv_namespaces]] id, commit, push
```

The deploy job **self-skips** while `REPLACE_WITH_KV_NAMESPACE_ID` is present,
so nothing goes red before the id lands.

`ADMIN_TOKEN` gates `DELETE /api/entries/<key>` only — the per-entry Delete
button on the page is deliberately unauthenticated so visitors can exercise the
demo. Setting the token does not disable those buttons:

```bash
cd zfb-example-kv-guestbook && pnpm install
pnpm exec wrangler secret put ADMIN_TOKEN
```

### password-gate — (optional) set the preview password

Without this, the Worker uses the dev fallback password `preview-open-sesame`.

```bash
cd zfb-example-password-gate && pnpm install
pnpm exec wrangler secret put SITE_PASSWORD
```

### workers-cache — (optional) set the purge token

Guards `POST /api/purge`.

```bash
cd zfb-example-workers-cache && pnpm install
pnpm exec wrangler secret put PURGE_TOKEN
```

### ai-summarizer — Workers AI

No id or GitHub secret beyond the shared token — the token's **Workers AI: Read**
permission is what lets the deployed Worker use the `AI` binding. The deploy job
runs `wrangler deploy --env ai` (the binding lives in the named `ai`
environment). Without AI access the route still returns its deterministic
fallback.

---

## Part 4 — Trigger and verify

- **Custom domains** — all live except kv-guestbook:

  | Repo | URL |
  | --- | --- |
  | blog | https://zfb-example-blog.takazudomodular.com/ |
  | corporate-website | https://zfb-example-corporate-website.takazudomodular.com/ |
  | webshop | https://zfb-example-webshop.takazudomodular.com/ |
  | ai-summarizer | https://zfb-example-ai-summarizer.takazudomodular.com/ |
  | json-api | https://zfb-example-json-api.takazudomodular.com/ |
  | password-gate | https://zfb-example-password-gate.takazudomodular.com/ (401 by design — the gate) |
  | reverse-proxy | https://zfb-example-reverse-proxy.takazudomodular.com/ |
  | workers-cache | https://zfb-example-workers-cache.takazudomodular.com/ |
  | kv-guestbook | https://zfb-example-kv-guestbook.takazudomodular.com/ |

  Each repo's deploy runs a post-deploy smoke check (`pnpm smoke`) against its
  own domain.
- **workers.dev URLs still work too.** Each Worker also keeps
  `https://<worker-name>.takazudo.workers.dev` (`workers_dev = true`), which is
  what makes per-deploy preview aliases route — `preview_urls` defaults to match
  `workers_dev`, so both are set explicitly. Note ai-summarizer's worker is
  named `zfb-example-ai-summarizer-ai`: it deploys with `--env ai`, so its
  custom-domain route lives under `[[env.ai.routes]]`, not at the top level.
- **New repo / first deploy**: push to `main` or re-run the **Deploy** workflow.
  The first `wrangler deploy` creates the Worker and attaches its route.

```bash
# re-run the latest Deploy run for a repo without a new commit
gh run list  --repo Takazudo/zfb-example-json-api --workflow Deploy --limit 1
gh run rerun <run-id> --repo Takazudo/zfb-example-json-api
```

Each repo's own `README.md` "Continuous deployment" section repeats the
specifics for that repo.
