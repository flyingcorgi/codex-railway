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

The seeded `$CODEX_HOME/config.toml` ships `approval_policy = "never"` and
`sandbox_mode = "danger-full-access"`. The container is disposable and isolated from your machine, so
the container *is* the sandbox — and an approval prompt you have to babysit is what makes a remote
box feel unlike a local one.

The trade-off, stated plainly: the agent can run any command and reach the network **inside this
container**. Don't leave secrets in the box that you wouldn't hand the agent.

To tighten it, edit `$CODEX_HOME/config.toml`:

```toml
sandbox_mode = "workspace-write"
approval_policy = "on-request"
```

`bubblewrap` is installed in the image, so that mode is available without a rebuild.

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
