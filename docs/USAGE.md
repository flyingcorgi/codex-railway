# Usage — run Codex on a remote box

This box is meant to be used exactly like your local terminal: connect, type `codex`, work,
disconnect. Nothing is lost when you leave — it lives on the `/workspace` volume.

## 1. One-time setup

After deploying the template:

1. **Confirm the volume** is attached at mount path `/workspace` (the template includes it).
2. **Authenticate Codex** — pick one:

   **A. ChatGPT plan** (Plus / Pro / Business / Edu / Enterprise) — use the plan you already pay for.
   Leave `OPENAI_API_KEY` unset, connect (step 2 below), then run once:
   ```bash
   codex login --device-auth
   ```
   It prints a short code and a URL; approve it at chatgpt.com from any device with a browser. The
   login is written to `$CODEX_HOME/auth.json` on the volume and is reused on every reconnect.

   > If this fails with a device-code error, your ChatGPT **workspace admin** has to enable *Device
   > Code Authorisation* in security settings first. If that's not an option, use path B.

   **B. API key** — set `OPENAI_API_KEY` in the service **Variables** tab. The box logs itself in on
   every boot. This bills at **OpenAI API rates, not against a ChatGPT plan**.

3. *(Optional)* `GITHUB_TOKEN` to auto-authenticate `gh` and HTTPS git, and `GIT_USER_NAME` /
   `GIT_USER_EMAIL` for commit identity.

Install the Railway CLI locally if you haven't:

```bash
npm i -g @railway/cli      # or: brew install railway
railway login
```

## 2. Connect

**Terminal:**

```bash
railway link                    # select this project + the codex service
railway ssh --session codex     # attach to the persistent tmux session
codex                           # launches the Codex TUI
```

`--session codex` is the important part: it puts you in a **tmux** session, so if your connection
drops, the agent keeps working and you reattach exactly where you were. Without it, closing the
terminal kills the TUI.

**Browser:** open the service's public URL and log in with user `codex` and the password from the
deploy logs (`[boot] browser terminal auth → ...`). You land in the *same* tmux session — same
scrollback, same running agent.

### Copying text out of the browser terminal

tmux runs with `mouse on` (so scrolling works), which means a plain drag is captured by **tmux**, not
by the browser. You get a highlight, but it lives in a tmux buffer inside the container — your local
clipboard never sees it. To select text the browser can actually copy, hold a modifier:

| Platform | Select | Copy |
|---|---|---|
| macOS | **Option** + drag | ⌘C |
| Windows / Linux | **Shift** + drag | Ctrl+Shift+C |

If you'd rather drag without a modifier, turn tmux's mouse handling off for a moment — at the cost of
scrolling until you turn it back on:

```
Ctrl-b : set -g mouse off      # plain drag now selects; Ctrl-b : set -g mouse on to restore
```

> The usual advice for this — tmux `set -g set-clipboard on`, which pushes copies to the client over
> **OSC 52** — does *not* work here. ttyd 1.7.7's bundled xterm.js registers no OSC 52 handler, so
> there is nothing on the browser side to receive the clipboard write. The modifier-drag above is the
> real mechanism, and `-t macOptionClickForcesSelection=true` in the Dockerfile is what enables it on
> macOS (xterm.js gates Option+drag behind that option and defaults it to false).

## 3. Working with repos

Clone into `/workspace/repos` so your code persists across redeploys:

```bash
cd /workspace/repos
git clone git@github.com:you/your-repo.git     # SSH (uses the box's generated key)
# or
gh repo clone you/your-repo                     # HTTPS via gh, if GITHUB_TOKEN is set
```

**Add the box's SSH key to GitHub** (for `git@github.com:` clones over SSH):

```bash
cat ~/.ssh/id_ed25519.pub      # copy this into GitHub → Settings → SSH keys
```

## 4. Sessions

Everything Codex remembers is on the volume, so this survives redeploys:

```bash
codex resume            # pick a previous session
codex resume --last     # continue the most recent one
codex fork --last       # branch off it without touching the original
```

## 5. Headless / one-shot

You don't have to use the TUI — `exec` runs a single prompt and exits:

```bash
codex exec "summarize what this repo does and list the entry points"
```

## 6. Sandbox & approvals

The seeded `$CODEX_HOME/config.toml` ships `approval_policy = "on-request"` and
`sandbox_mode = "danger-full-access"`. Set `CODEX_APPROVAL_POLICY=never` in Railway Variables *before
first boot* if you want unattended "YOLO mode" instead — or edit `config.toml` in the box at any time.

**Why approvals are on by default.** It's tempting to say "the container is disposable, so let the
agent do anything." That's only half true. This box stores credentials that reach **outside** the
container:

| In the box | Reaches |
|---|---|
| `$CODEX_HOME/auth.json` | your real ChatGPT account |
| `/workspace/.ssh/id_ed25519` | whatever GitHub access you granted that key |
| `GITHUB_TOKEN` (if set) | your GitHub account |

Codex's sandbox can't restrict network access here (see below), so with `approval_policy = "never"` a
prompt injection in any repo, issue, or web page the agent reads can exfiltrate all three with no
friction — and because they live on the volume, a redeploy doesn't undo it. `on-request` puts a human
in that path.

If you do run with `never`, treat the box as holding live secrets: prefer a fine-scoped
`GITHUB_TOKEN` over a broad one, and don't point it at repos you can't afford to have force-pushed.

**Don't switch `sandbox_mode` to `workspace-write` here — it cannot work on Railway.** Codex's Linux
sandbox is implemented with `bubblewrap`, and bwrap can't create a user namespace inside a Railway
container:

```
$ bwrap --ro-bind / / --dev /dev echo ok
bwrap: Creating new namespace failed: Operation not permitted
```

That's a platform restriction (Railway blocks the syscall regardless of
`/proc/sys/user/max_user_namespaces`), not something a config change fixes. `codex doctor` will
happily report a healthy sandbox in `workspace-write` mode and then fail on the first command it
tries to run, so the failure is worse than it looks.

`danger-full-access` is the only working mode on Railway. If you need real sandboxing, the isolation
boundary has to be the container itself — deploy a second service for untrusted work rather than
loosening or tightening this one.

You *can* still raise friction usefully without touching `sandbox_mode`:

```toml
approval_policy = "on-request"   # ask before running commands; sandboxing stays off
```

## 7. Housekeeping

```bash
codex --version         # which pinned build you're on
codex doctor            # diagnose install / config / auth / runtime health
df -h /workspace        # check volume usage
```

To upgrade Codex, bump `ARG CODEX_VERSION` in `codex/Dockerfile` and redeploy — the pin is
deliberate, so `codex update` inside the box is undone by the next rebuild.

## Notes & gotchas

- **Always work under `/workspace`.** Files written elsewhere (e.g. `/root`, `/tmp`) are **lost on
  redeploy** — only the volume persists.
- `railway ssh` runs a login shell, which sources `/etc/profile.d/00-codex-env.sh`; that's how
  `CODEX_HOME`, your locale and your keys reach `codex`. If something looks missing, re-check the
  Variables tab and reconnect.
- **Two clients, one session.** The browser and SSH attach to the same tmux session by design. If
  you'd rather have separate ones, use a different name: `railway ssh --session scratch`.
- **Rotating the browser password:** set `CODEX_WEB_PASSWORD` in Variables (redeploys), or edit
  `/workspace/.codex-web-password` and restart. To make the box private again, remove the service's
  public domain in Railway → only `railway ssh` remains.
- **`OPENAI_API_KEY` never overrides an existing login.** If you device-auth'd with a ChatGPT plan,
  a leftover key variable won't silently switch you to API billing.
