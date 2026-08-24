# Publishing to the Railway marketplace

Requires **Railway CLI ≥ 5.x** (`railway templates` did not exist in 4.x).
Verify with `railway --version`; upgrade with `brew upgrade railway` if needed.

> **Do not publish until [`VERIFICATION.md`](VERIFICATION.md) is fully signed off.** This template's
> whole pitch is that the remote `codex` behaves like the local one; shipping it unverified is how a
> template ends up with a low deploy-success rate it never recovers from.

## Prerequisites

1. **A PUBLIC GitHub repo.** Deployers clone it, and the marketplace card image must be reachable.
   This one lives at <https://github.com/yuting1214/codex-railway>.
2. **A project with a service linked to that GitHub repo**, with **root directory set to `codex`**
   (the monorepo subdir holding the Dockerfile). A service deployed only via local `railway up` has
   no git source to template.
3. **A volume** on that service mounted at `/workspace`.
4. **A public domain** on the service (ttyd needs it; the box is still usable without one).
5. Deploy once and verify cold-start.

## Create the draft

```bash
railway link                       # link the project whose service points at the repo
railway templates create --json    # → returns an unpublished draft { id }; note the id
```

In a TTY this opens the dashboard template editor — confirm the captured variables
(`OPENAI_API_KEY`, `CODEX_ACCESS_TOKEN`, `GITHUB_TOKEN`, `GIT_USER_NAME`, `GIT_USER_EMAIL`,
`CODEX_WEB_USERNAME`, `CODEX_WEB_PASSWORD`) are all **optional**, and that the volume mount at
`/workspace` is present.

> Note: `templateGenerate` captures variable *names* only, never values — so no secrets leak.

## Publish

```bash
railway templates publish <DRAFT_ID> \
  --category AI/ML \
  --description "Run the OpenAI Codex CLI on a persistent Railway box, TUI or browser" \
  --readme-file TEMPLATE.md \
  --image https://raw.githubusercontent.com/yuting1214/codex-railway/<sha>/assets/card.png \
  --json
```

- **Category** must be `AI/ML` (from the fixed list).
- **Description** must be ≤ 75 characters — the one above is 71.
- Use a **commit-pinned** raw image URL (`/<sha>/`, not `/main/`) so the card resolves immediately.

The command returns the published `{ code }`; the deploy URL is then
`https://railway.com/deploy/<code>` and the button is:

```md
[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/<code>)
```

## Updating later

- **Metadata only** (description/readme/image/category):
  ```bash
  railway templates publish <id> --category AI/ML --readme-file TEMPLATE.md --json
  ```
- **Build changes** (Dockerfile/entrypoint, Codex version bump): push to the GitHub repo and redeploy
  the source service.
- **Renaming or changing captured variables**: regenerate from the updated project → publish new →
  delete old (reclaims the same slug, keeping the URL stable).

## Keeping the Codex pin current

Codex ships several releases a week. The pin in `ARG CODEX_VERSION` is deliberate — but a stale pin
is its own failure mode. Check periodically:

```bash
npm view @openai/codex version
gh api repos/openai/codex/releases --jq '.[0:5][] | .tag_name + " " + .published_at'
```

Bump the ARG, redeploy, re-run the cold-start checklist, then commit.

## Monitoring adoption

There is **no CLI/API** for template metrics. Scrape the public page:

```
WebFetch https://railway.com/deploy/<code>
  → parse: N total projects · N active · N recent · N% deploy success
```
