# Verification — what must be proven before publishing

The design is settled and the image builds. These four items are the ones that can only be trusted
after they're exercised, and **all four must pass on a real Railway deploy before this template goes
to the marketplace.** Codex has no `codex web`, so this template's entire value is TUI fidelity — if
any of these fails, the promise doesn't hold.

Status legend: ⬜ unverified · 🟡 verified locally only · ✅ verified on Railway · ❌ broken

---

## Already verified locally (arm64 Docker, image `codex-railway:scaffold-test`)

Railway builds amd64, so none of this is a substitute for a live deploy — but these are settled.

- 🟡 **Image builds clean**; `codex --version` → `codex-cli 0.149.1` matches `ARG CODEX_VERSION`;
  `ttyd --version` passes.
- 🟡 **`config.toml.default` is valid for the pinned binary.** `codex app-server --strict-config
  --listen off` accepts it and fails only later at the transport stage. Control test: appending
  `totally_bogus_key = 123` produces `unknown configuration field`, proving the validator actually
  reads the file. So `approval_policy = "never"` and `sandbox_mode = "danger-full-access"` are
  confirmed-good spellings in 0.149.1.
- 🟡 **`cli_auth_credentials_store` is a scalar, not a table.** Probing with an invalid value made
  the binary enumerate its own accepted set: `` expected one of `file`, `keyring`, `auto`,
  `ephemeral` ``. A `[cli_auth_credentials_store]` table is rejected. Set to `"file"` so auth.json
  lands on the volume instead of a keyring that wouldn't survive a redeploy.
- 🟡 **Boot is idempotent.** Second boot on the same volume does not re-seed `config.toml`, does not
  regenerate the SSH key, and reuses the generated web password.
- 🟡 **Login-shell env is correct** inside the container: `CODEX_HOME=/workspace/codex`,
  `TERM=xterm-256color`, `LANG=en_US.UTF-8`, lands in `/workspace/repos`; `~/.codex` symlink resolves
  to the volume.
- 🟡 **ttyd basic auth works**: no creds → 401, wrong creds → 401, correct creds → 200.
- 🟡 **tmux session `codex` exists from boot** and `tmux new-session -A -s codex` attaches to it
  rather than creating a second one (`tmux ls` stays at 1 session) — this is what makes the
  "one session, two doors" claim hold.
- 🟡 **`codex login status` exits non-zero cleanly when unauthenticated**, so the entrypoint's
  "don't stomp an existing login" guard behaves under `set -e`.

---

## 1. ❌→✅ bubblewrap CANNOT work in a Railway container — resolved, docs corrected

**Verified on a live Railway deploy (amd64, Debian 12, `asia-southeast1`).** bwrap cannot create a
user namespace, so Codex's `workspace-write` sandbox is unavailable on this platform:

```
$ bwrap --ro-bind / / --dev /dev echo ok
bwrap: Creating new namespace failed: Operation not permitted

$ codex sandbox echo hello
bwrap: Failed to make / slave: Permission denied
```

This is *not* a missing-kernel-feature problem — the container reports
`/proc/sys/user/max_user_namespaces = 1573664` and `unprivileged_userns_clone = 1`. Railway blocks
it at the seccomp/capability layer, so no config change fixes it.

**The dangerous part:** `codex doctor -c sandbox_mode=workspace-write` reports a *clean* sandbox and
drops its warning — the failure only shows up when the agent runs its first command. A user
following "just switch to workspace-write" would get a box that looks healthy and breaks on use.

- [x] `bwrap` test run on the deployed container → fails as above.
- [x] Under the shipped default, `codex doctor` reports
      `⚠ sandbox filesystem unrestricted · network enabled` — i.e. the permissive mode is active and
      accepted, no startup error.
- [x] ~~Confirm the exact key spellings `approval_policy` / `sandbox_mode`~~ — done locally via
      `--strict-config` + control test.
- [x] **Docs corrected** in `config.toml.default`, `USAGE.md` §6, `ARCHITECTURE.md`, `README.md`:
      `workspace-write` is now documented as *unavailable on Railway* rather than offered.
- [ ] **Still open:** confirm the agent's normal exec path works under `danger-full-access` — needs
      auth (item 3). `codex sandbox` fails in *both* modes because that subcommand always sandboxes
      by definition; that does not prove the normal loop is broken, and doctor suggests it isn't.
- [ ] **Then decide:** remove `bubblewrap` from the image (dead weight, ~is unusable here) — held
      until the line above is confirmed, so we don't remove something Codex turns out to need.

## 1b. 🟡 Bonus finding: `ripgrep` is redundant

`codex doctor` shows Codex ships and prefers its **own bundled `rg`**
(`…/codex-linux-x64/vendor/x86_64-unknown-linux-musl/codex-path/rg`). The apt `ripgrep` in the
Dockerfile is never used by Codex. Keep it only as a convenience for the human at the shell —
otherwise drop it alongside `bubblewrap`.

## 2. 🟡 `railway ssh --session` + Codex TUI rendering — mostly verified

- [x] **`railway ssh --session codex` targets the existing session, not a new one.** `tmux ls` before
      and after shows exactly one session with an unchanged creation timestamp (the boot-created
      one). The flag's failure message in a non-TTY context is tmux's own
      `open terminal failed: not a terminal`, confirming it routes into tmux with our session name.
- [x] **The tmux login shell environment is correct** — captured from the real session via
      `tmux send-keys printenv` + `capture-pane`:
      `CODEX_HOME=/workspace/codex`, `LANG`/`LC_ALL=en_US.UTF-8`, `TERM=tmux-256color`, prompt in
      `/workspace/repos`. So `/etc/profile.d/00-codex-env.sh` is sourced on the path users actually
      take.
- [x] Pre-installed tmux is used — Railway did not attempt its own install.
- [x] `codex doctor` on the box reports `effective locale en_US.UTF-8`, confirming the locale setup.
- [ ] **Needs a human terminal:** TUI renders correctly (box-drawing, 256 colours, no mojibake) and
      reflows on resize (SIGWINCH). Not provable from a non-TTY tool session.

> **Note for whoever runs the manual check:** `railway ssh -s <svc> -- <cmd>` mangles any argument
> containing quotes, pipes, redirects or semicolons (CLI 5.23.1 — an early `bash -lc '…'` probe
> falsely showed `CODEX_HOME` empty because of this). Multi-word commands with plain flags are fine.
> To run anything complex, use `tmux send-keys` + `tmux capture-pane -p -t codex`.

**Fallback if broken:** if `--session` doesn't share the session, document the browser and SSH doors
as independent sessions and drop the "same session" claim.

## 3. ⬜ `codex login --device-auth` end-to-end through ttyd

- [x] **ttyd basic auth works on the live public domain** (`https://codex-production-0eba.up.railway.app`
      during testing): no creds → 401, wrong creds → 401, correct creds → 200 serving
      `<title>ttyd - Terminal</title>`. The password was auto-generated at first boot and printed to
      the deploy logs as designed (`[boot] browser terminal auth → user: codex password: …`).
- [ ] Opening the public domain in a browser lands in the tmux session (needs a human browser).
- [ ] `codex login --device-auth` runs in the browser terminal, prints a readable code + URL, and
      does not hang trying to open a browser (the `xdg-open` shim should cover this).
- [ ] Approving at chatgpt.com completes the login; `codex login status` reports authenticated.
- [ ] The credential lands in `$CODEX_HOME/auth.json` on the **volume** — not an OS keyring.
      `cli_auth_credentials_store = "file"` is now set explicitly for this reason; confirm it
      actually takes effect after a real login.
- [ ] Repeat from a phone browser — this is the reason the browser door exists.

**Fallback if broken:** document the API-key path as primary and device-auth as best-effort.

## 3b. ✅ Device auth verified end-to-end (live, ChatGPT plan)

- [x] Browser terminal opened on the public domain, TUI rendered correctly (box-drawing, colour,
      `directory: /workspace/repos`), `codex login --device-auth` completed against a real ChatGPT
      account, and the agent answered real prompts.
- [x] **This also closes the last gap in item 1:** the normal agent exec path works fine under
      `sandbox_mode = "danger-full-access"`. Only the `codex sandbox` subcommand is unusable.
- [x] `codex login status` → `Logged in using ChatGPT`.
- [x] `auth.json` is on the **volume** (`/workspace/codex/auth.json`, 4200 B, mode 600) — so
      `cli_auth_credentials_store = "file"` took effect, not a keyring.
- [x] Login **survived a redeploy**: `[boot] codex authenticated (existing login on volume).`

## 3c. ❌→✅ SECURITY: `shell_snapshots` leaked all service variables — fixed

Confirmed on the live box, not just from source: `$CODEX_HOME/shell_snapshots/*.sh` were **mode 0644
(world-readable)** on the persistent volume and contained `CODEX_WEB_PASSWORD` and 22 `RAILWAY_*`
variables in plaintext. Any `OPENAI_API_KEY` / `GITHUB_TOKEN` would be there too. Codex writes these
via `declare -xp` and never reuses them across runs.

**Fixed** in `entrypoint.sh` (commit `bc1d5e1`): `shell_snapshots/` and `packages/` are pruned every
boot. ⬜ **Not yet verified live** — the deploy carrying this fix has not run.

## 4. 🟡 `codex resume` after a redeploy — data confirmed, picker not yet exercised

- [x] **Session rollouts survive a redeploy on the volume.** After two real conversations and a
      redeploy, both files were still present:
      `/workspace/codex/sessions/2026/08/24/rollout-2026-08-24T{05-04-49,08-35-35}-*.jsonl`.
      `sessions/*.jsonl` is the source of truth; the SQLite DBs are a derived cache rebuilt by
      startup backfill, so this is the data that matters.
- [ ] **Remaining:** exercise the picker itself — `codex resume` needs a TTY (`Error: stdin is not a
      terminal` from a tool session), so run it from the browser terminal or an interactive
      `railway ssh --session codex` and confirm the pre-redeploy conversation restores.
- [ ] Confirm which paths under `$CODEX_HOME` are actually required (`sessions/`,
      `session_index.jsonl`, which SQLite DBs) — the whole directory is persisted, so this is about
      knowing what matters, not what to add.
- [ ] Check for anything machine-bound that a whole-directory symlink shouldn't carry across
      containers (`installation_id`, `version.json`, `shell_snapshots/`, `tmp/`). If any of these
      misbehave on restore, exclude them in `entrypoint.sh`.
- [ ] SQLite WAL files: confirm a container killed mid-session doesn't leave a stale lock that
      breaks the next boot.

**Fallback if broken:** exclude the offending subpaths from the volume and document reduced
session persistence.

---

---

## Handoff — what the next deploy must verify

Commit `bc1d5e1` (on-request default + `shell_snapshots` pruning) is **committed but never
deployed**. On the next deploy, check:

- [ ] Boot log shows `[boot] existing config.toml kept (approval_policy = "never")` on the existing
      volume — proving user edits are not clobbered.
- [ ] On a **fresh volume**, boot log shows
      `[boot] seeding … (first boot, approval_policy=on-request)` and the TUI shows **no YOLO
      banner**.
- [ ] Setting `CODEX_APPROVAL_POLICY=never` on a fresh volume seeds `never`; setting a garbage value
      logs the warning and falls back to `on-request` instead of producing a box that won't start.
- [ ] `$CODEX_HOME/shell_snapshots` is **absent** after boot.
- [ ] `codex resume` restores a pre-redeploy conversation from an interactive terminal.
- [ ] With `OPENAI_API_KEY` set *and* an existing ChatGPT login, boot logs say the existing login was
      left alone (no silent switch to API billing).

### ⚠️ Gotcha that cost time: `railway up` deploys the COMMITTED tree

Uncommitted working-tree edits are **not** uploaded. A deploy ran, built a new image, reported
SUCCESS and RUNNING — and the container still had the previous `entrypoint.sh`, byte-identical to
`HEAD`. **Commit before `railway up`**, and verify the running container actually has your change
(e.g. `railway ssh -s <svc> -- wc -c /usr/local/bin/entrypoint.sh`) rather than trusting deploy
status.

### Scratch project

`codex-verify-scratch` (project `11856be9-c5ad-459b-8206-f284171b6fc2`, service `codex`) is **left
running** at the user's request, with a real ChatGPT login on its volume and
`approval_policy = "never"` still seeded from the original first boot. It bills while it runs.

---

## Cold-start checklist (run after the four above)

- [ ] `railway ssh --session codex` connects and lands in `/workspace/repos`.
- [ ] `codex --version` matches `ARG CODEX_VERSION`.
- [ ] `codex exec "hello"` returns a model response.
- [ ] `git clone` into `/workspace/repos` succeeds and survives a redeploy.
- [ ] Browser terminal basic auth rejects a wrong password.
- [ ] With `OPENAI_API_KEY` set *and* an existing device-auth login, boot logs say the existing
      login was left alone.
