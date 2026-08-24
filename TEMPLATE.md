# Deploy and Host OpenAI Codex CLI on Railway

[Codex CLI](https://github.com/openai/codex) is **OpenAI's coding agent for the terminal** — it reads
your repo, writes and edits code, runs commands, and opens pull requests. This template runs the real
`codex` TUI on a persistent Railway box with **two ways in**: `railway ssh` from your terminal, or a
**browser terminal** on a public domain — both attached to the same tmux session, with repos, auth
and sessions on a volume that survives redeploys.

## About Hosting OpenAI Codex CLI

One container runs the **actual Codex CLI**, not a reimplementation of it. `ttyd` serves a persistent
`tmux` session on a password-protected Railway domain, and `railway ssh --session codex` attaches to
that very same session — so a dropped connection, a closed tab, or a switch from laptop to phone
never loses your place. A `/workspace` volume keeps repos, `config.toml`, `auth.json` and your Codex
session history across redeploys, so `codex resume` still works. `git` and the GitHub CLI are
preinstalled, and the Codex version is pinned so two deploys of the same commit build the same agent.
The deploy form asks for no credentials at all — you authenticate inside the box the same way you do
locally, with `codex login --device-auth` on your ChatGPT plan, or by adding an `OPENAI_API_KEY`
variable if you would rather bill at API rates.

## Why Deploy Codex CLI on Railway?

- **The real TUI, not a clone** — you type `codex` and get exactly what you get locally. Codex ships
  no self-hostable web UI; rather than fake one, this template gives you the genuine terminal, twice.
- **Your laptop can sleep** — the agent keeps working; reattach from the browser or `railway ssh`
  and pick up mid-task.
- **Nothing is lost on disconnect** — tmux holds the session, and both doors attach to it.
- **Sign in from a phone** — the browser terminal makes `codex login --device-auth` work without
  installing anything, anywhere.
- **Persistent** — repos, auth and `codex resume` history sit on a volume, so a redeploy never logs
  you out or loses your working tree.
- **Secure by default** — the browser terminal sits behind HTTP basic auth with a unique password
  generated for your deploy and shown in your Variables tab; SSH is Railway-authenticated. Codex
  runs with `approval_policy = "on-request"`, so the agent asks before it acts.

## Common Use Cases

- **A cloud coding-agent workstation** reachable from a terminal *or* a browser tab.
- **Long-running refactors or migrations** that keep going regardless of your local machine.
- **A shared, reproducible agent environment** with a pinned Codex version across repositories.

## Dependencies for Codex CLI Hosting

- **A ChatGPT plan** (Plus / Pro / Business / Edu / Enterprise) for `codex login --device-auth`, *or*
  an `OPENAI_API_KEY` (billed at API rates).
- The **Railway CLI** for terminal access (`railway ssh`); the browser terminal needs only a browser.

### Deployment Dependencies

- [Codex CLI](https://github.com/openai/codex) — OpenAI's open-source coding agent
  (`@openai/codex` on npm, version-pinned in the image).
- [ttyd](https://github.com/tsl0922/ttyd) — serves the terminal over HTTP.
- [GitHub CLI](https://cli.github.com/) — bundled so the agent can manage issues and pull requests.

### Why This Template?

One click gives you a persistent Codex box you can reach from a terminal or a browser, with a pinned
agent version and credentials, repos and session history that outlive every redeploy. Source and
docs: <https://github.com/yuting1214/codex-railway>.
