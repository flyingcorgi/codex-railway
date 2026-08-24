# Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  YOUR MACHINE / PHONE                                            │
│   browser ──────────────┐            railway ssh ─────────┐      │
└─────────────────────────┼──────────────────────────────-──┼──────┘
        Railway public domain (HTTPS)      Railway authenticated SSH
                          ▼                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│  RAILWAY CONTAINER  (one service)                                │
│                                                                  │
│   CMD ▶ ttyd --port $PORT --credential u:p  tmux new -A -s codex │
│            └─ basic auth ─┐                                      │
│                           ▼                                      │
│                   ┌─────────────────────┐                        │
│                   │ tmux session "codex"│ ◀── railway ssh        │
│                   │   $ codex   (TUI)   │      --session codex   │
│                   └─────────────────────┘                        │
│                     ▲ both doors, one session                    │
│                                                                  │
│   tooling: @openai/codex · tmux · ttyd · bubblewrap · git · gh   │
│                                                                  │
│   CODEX_HOME ──▶  /workspace volume (persists across deploys)    │
│     $CODEX_HOME  = /workspace/codex   (~/.codex symlinked too)   │
│       auth.json · config.toml · sessions/ · history.jsonl        │
│     ~/.ssh                   → /workspace/.ssh                   │
│     repos                     /workspace/repos                   │
└──────────────────────────────────────────────────────────────────┘
```

## Components

- **Dockerfile** — `node:20-slim` + `git`, `gh`, `openssh-client`, `tmux`, `bubblewrap`, `locales`,
  `ripgrep`, and two binaries fetched at build time: the **Codex CLI** (npm, pinned via
  `ARG CODEX_VERSION`) and **ttyd** (upstream static release binary, pinned via `ARG TTYD_VERSION`).
  `ENTRYPOINT` runs the boot script; `CMD` runs ttyd (the main process, on `$PORT`).
- **entrypoint.sh** — runs on every boot:
  1. Creates the `/workspace` layout, exports `CODEX_HOME=/workspace/codex`, and symlinks
     `~/.codex` and `~/.ssh` onto the volume.
  2. Seeds `config.toml` from `config.toml.default` — **first boot only**, never overwriting edits.
  3. Generates an ed25519 SSH key on first boot and trusts `github.com`.
  4. Authenticates `gh` from `GITHUB_TOKEN` (if set) and sets git identity.
  5. Seeds Codex auth from `OPENAI_API_KEY` **only if no login already exists**, so an interactive
     `codex login --device-auth` is never stomped.
  6. Resolves the ttyd basic-auth password (generated + persisted on the volume if unset) and writes
     `/etc/profile.d/00-codex-env.sh` so login shells export `CODEX_HOME`, `TERM`, the locale and
     provider vars, and land in `/workspace/repos`.
- **tmux.conf** — login shells inside tmux (so `/etc/profile.d` is sourced), mouse on, 256-colour,
  `aggressive-resize` so a second attached client doesn't cramp the TUI.
- **railway.json** — Dockerfile builder + restart-on-failure.
- **Volume** — mounted at `/workspace`; the single source of persistent state.

## Design choices

- **Fidelity over novelty.** The deliverable is "`codex` here behaves like `codex` on your laptop".
  No custom frontend, no wrapper protocol — the real TUI, reached two ways.
- **One tmux session, two doors.** ttyd and `railway ssh --session codex` attach to the same session,
  so a dropped SSH connection, a closed browser tab, or switching devices never loses your place.
  Want independent sessions instead? Use a different name: `railway ssh --session scratch`.
- **No custom web UI.** Codex ships no self-hostable browser UI. Building one on the `[experimental]`
  `app-server` WebSocket protocol would mean owning a frontend against an interface that churns
  weekly — and `--listen ws://0.0.0.0` has no built-in auth. Rejected deliberately.
- **Version-pinned.** Codex ships several releases a week; `ARG CODEX_VERSION` keeps two deploys of
  the same commit identical. Bump it on purpose.
- **The container is the sandbox.** Default config is `approval_policy = "never"` +
  `sandbox_mode = "danger-full-access"`, because an approval prompt you have to babysit is the
  fastest way to make a remote box feel unlike a local one. `bubblewrap` is installed anyway so
  `workspace-write` remains a one-line config change.
- **Secure public surface.** ttyd hands out a writable shell, so it is always behind basic auth with
  an auto-generated, volume-persisted password. Drop the public domain to go SSH-only.
- **Volume-first persistence.** Codex keeps everything under one directory, so a single
  `CODEX_HOME` redirect covers auth, config, sessions and history.
