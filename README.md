# Codex on Railway

> **Status: pre-publish.** The image builds and the design is settled, but the four cold-start
> unknowns in [`docs/VERIFICATION.md`](docs/VERIFICATION.md) must be signed off on a real deploy
> before this goes to the marketplace.

A one-click, self-hosted home for **[OpenAI Codex CLI](https://github.com/openai/codex)** — the same
`codex` you run locally, on a box that keeps working when your laptop sleeps.

The whole idea is **fidelity**: you type `codex`, you get the TUI you already know. There are two
doors into the *same* container, and both land you in the *same* tmux session:

- 💻 **Terminal** — `railway ssh --session codex`, then type `codex`.
- 🌐 **Browser** — open the public Railway domain for the same terminal in a tab (basic auth). No
  Railway CLI needed, which is also how you complete `codex login --device-auth` from a phone.

Sessions, auth, config and repos live on a `/workspace` volume, so `codex resume` still works after a
redeploy.

> **There is no `codex web`.** Codex has no browser UI to self-host — "Codex Web" is OpenAI's hosted
> product. The browser door here is a real terminal (ttyd + xterm.js), not a chat app. That's a
> deliberate, honest choice: it's the *same* TUI, not a lesser reimplementation of it.

---

## Quick start

1. **Deploy** this template. It provisions the service, a **Volume** at `/workspace`, and a public
   domain.
2. **Authenticate** — pick one:
   - **ChatGPT plan** (Plus/Pro/Business): leave `OPENAI_API_KEY` unset, then run `codex login
     --device-auth` once inside the box and approve the code at chatgpt.com.
   - **API key**: set `OPENAI_API_KEY` in **Variables** and the box logs itself in on boot. Bills at
     API rates, *not* against a ChatGPT plan.

   Optional: `GITHUB_TOKEN`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, `CODEX_WEB_PASSWORD`.
3. **Browser:** open the service's public URL. Log in with user `codex` and the password printed in
   the **deploy logs** (`[boot] browser terminal auth → ...`).
4. **Terminal:** from your machine —
   ```bash
   railway link                    # pick this project/service
   railway ssh --session codex     # attach to the tmux session
   codex                           # the Codex TUI
   ```
5. Clone a repo and start working — use `/workspace/repos` so it persists:
   ```bash
   cd /workspace/repos && git clone git@github.com:you/your-repo.git
   ```

## What's in the box

| Tool | Why |
|------|-----|
| **Codex CLI** (`@openai/codex`, version-pinned) | `codex` (TUI), `codex exec` (headless), `codex resume` / `fork` |
| **tmux** | your session survives a dropped connection, a closed browser tab, and a redeploy of *you* |
| **ttyd** | serves that tmux session on the public domain, behind basic auth |
| **bubblewrap** | Codex's Linux sandbox, so `workspace-write` mode is available if you want it |
| **git** + **SSH key** | clone/commit; an ed25519 key is generated on first boot (`~/.ssh/id_ed25519.pub`) |
| **GitHub CLI** (`gh`) | `gh pr create`, `gh issue` — auto-authenticated from `GITHUB_TOKEN` |

## How it works

- The container's main process is **ttyd** serving `tmux new -A -s codex` on `$PORT`, mapped to the
  public Railway domain and protected by HTTP basic auth (`CODEX_WEB_PASSWORD`, auto-generated and
  persisted on the volume if unset). This is what keeps the service alive.
- `railway ssh` reaches the **same** container independently of that process; `--session codex`
  attaches to the same tmux session, so both doors show the same work.
- `CODEX_HOME` points at `/workspace/codex` (and `~/.codex` is symlinked there), so `auth.json`,
  `config.toml`, `sessions/` and history all persist.
- A default `config.toml` is seeded on **first boot only** with `approval_policy = "never"` and
  `sandbox_mode = "danger-full-access"` — the container *is* the sandbox. Edit it in the box; it is
  never overwritten. See [`docs/USAGE.md`](docs/USAGE.md) to tighten it.

See [`docs/USAGE.md`](docs/USAGE.md) for the walkthrough, [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
for how it's wired, [`docs/VERIFICATION.md`](docs/VERIFICATION.md) for what still needs proving on a
live deploy, and [`docs/PUBLISH.md`](docs/PUBLISH.md) to publish it to the Railway marketplace.

## Layout

```
codex-railway/
├── codex/                  ← the deployable (Railway root directory)
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── config.toml.default ← seeded to the volume on first boot
│   ├── tmux.conf
│   ├── railway.json
│   └── .env.example
├── docs/
└── assets/
```
