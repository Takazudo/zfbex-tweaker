# Cloudflare shared token + per-repo env setup

Setup guide for deploying the whole **zfb-example** family from GitHub Actions
using **one shared Cloudflare API token**. All repos deploy to the **same
Cloudflare account**, so a single account-scoped token works everywhere; each
repo just needs the same two GitHub Actions secrets.

The family is 9 repos:

| Repo | Deploy target |
| --- | --- |
| [zfb-example-blog](https://github.com/Takazudo/zfb-example-blog) | Cloudflare **Pages** (static) |
| [zfb-example-corporate-website](https://github.com/Takazudo/zfb-example-corporate-website) | Cloudflare **Pages** (static) |
| [zfb-example-webshop](https://github.com/Takazudo/zfb-example-webshop) | Cloudflare **Workers** (static assets) + **D1** |
| [zfb-example-ai-summarizer](https://github.com/Takazudo/zfb-example-ai-summarizer) | **Workers** (static assets) + Workers AI |
| [zfb-example-json-api](https://github.com/Takazudo/zfb-example-json-api) | **Workers** (static assets) |
| [zfb-example-kv-guestbook](https://github.com/Takazudo/zfb-example-kv-guestbook) | **Workers** (static assets) + KV |
| [zfb-example-password-gate](https://github.com/Takazudo/zfb-example-password-gate) | **Workers** (static assets, gate) |
| [zfb-example-reverse-proxy](https://github.com/Takazudo/zfb-example-reverse-proxy) | **Workers** (static assets) |
| [zfb-example-workers-cache](https://github.com/Takazudo/zfb-example-workers-cache) | **Workers** (static assets) + Cache |

> The 3 Pages repos (blog / corporate-website / webshop) already have secrets
> set and deploy today. The 6 Workers repos are freshly extracted and have **no
> secrets yet** — their `deploy` job self-skips until you add them.

---

## Part 1 — Create the shared API token

Cloudflare dashboard → **My Profile → API Tokens → Create Token → Create Custom
Token**. Because one token covers Pages, Workers, KV, Workers AI, and D1 across
the account, it needs the union of every repo's permissions:

| Type | Permission | Access | Why |
| --- | --- | --- | --- |
| Account | **Cloudflare Pages** | Edit | blog, corporate-website (`wrangler pages deploy`) |
| Account | **Workers Scripts** | Edit | webshop + all 6 Workers repos (`wrangler deploy`) |
| Account | **Workers KV Storage** | Edit | kv-guestbook (create namespace + bind) |
| Account | **Workers AI** | Read | ai-summarizer (`AI` binding) |
| Account | **D1** | Edit | webshop (`wrangler d1 migrations apply`) |
| Account | **Account Settings** | Read | wrangler resolves account metadata |

- **Account Resources**: Include → *your account*.
- **Zone Resources**: none needed — every site uses `*.pages.dev` /
  `*.workers.dev`, not a custom domain. (Add **Zone · Workers Routes · Edit**
  only if you later attach a custom domain.)
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
| blog | — | — | Pages: Edit |
| corporate-website | — | — | Pages: Edit |
| webshop | D1 `webshop` + `webshop-preview` (ids already committed; re-provision via its `d1-bootstrap.yml`) | — | Workers Scripts: Edit, D1: Edit |
| ai-summarizer | — (Workers AI is an account feature, no id) | — | Workers Scripts: Edit, Workers AI: Read |
| json-api | — | — | Workers Scripts: Edit |
| kv-guestbook | **KV namespace** → paste id into `wrangler.toml` | `ADMIN_TOKEN` | Workers Scripts: Edit, KV: Edit |
| password-gate | — | `SITE_PASSWORD` (optional; has a dev fallback) | Workers Scripts: Edit |
| reverse-proxy | — (`PROXY_ORIGIN` is a public `[vars]` value) | — | Workers Scripts: Edit |
| workers-cache | — | `PURGE_TOKEN` (optional) | Workers Scripts: Edit |

### kv-guestbook — provision KV + set admin token

The committed `wrangler.toml` has `id = "REPLACE_WITH_KV_NAMESPACE_ID"`; the
deploy job **self-skips** while that placeholder is present. Provision, then
commit the real id:

```bash
cd zfb-example-kv-guestbook
pnpm install
pnpm exec wrangler kv namespace create zfb-example-kv-guestbook
# → copy the printed id into wrangler.toml's [[kv_namespaces]] id, commit, push

pnpm exec wrangler secret put ADMIN_TOKEN   # admin delete token (Cloudflare-side)
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

- **Pages repos** (blog, corporate-website): already live at
  `https://zfb-example-<name>.pages.dev/`.
- **Workers repos** (webshop + the 6 new ones): after secrets (and any resource
  id) are set, push to `main` or re-run the **Deploy** workflow. First
  `wrangler deploy` *creates* the Worker; the account subdomain is `takazudo`,
  so the URL is `https://<worker-name>.takazudo.workers.dev` (ai-summarizer's
  worker is `zfb-example-ai-summarizer-ai`). webshop is already live at
  `https://zfb-example-webshop.takazudo.workers.dev/`.

```bash
# re-run the latest Deploy run for a repo without a new commit
gh run list  --repo Takazudo/zfb-example-json-api --workflow Deploy --limit 1
gh run rerun <run-id> --repo Takazudo/zfb-example-json-api
```

Each repo's own `README.md` "Continuous deployment" section repeats the
specifics for that repo.
