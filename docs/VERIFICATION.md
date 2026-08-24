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

## 1. ⬜ bubblewrap / sandbox behavior in a Railway container

**The one genuine unknown.** Codex on Linux uses `bubblewrap` (bwrap) for `workspace-write`, and
bwrap needs unprivileged user namespaces — which containers often don't grant. Railway runs
containers unprivileged.

- [ ] `bwrap --ro-bind / / --dev /dev echo ok` succeeds inside the deployed container.
- [ ] If it fails: confirm Codex still runs normally under `sandbox_mode = "danger-full-access"`
      (the shipped default) and doesn't hard-error on startup.
- [x] ~~Confirm the exact key spellings `approval_policy` / `sandbox_mode` against the pinned
      version~~ — done locally via `--strict-config` + control test (see above).
- [ ] Decide whether `bubblewrap` stays in the image. If bwrap can't work on Railway at all, it's
      dead weight and `workspace-write` should be documented as unavailable rather than offered.

**Fallback if broken:** drop `workspace-write` from the docs; keep the default config as-is. The
template still works — this only removes an option users were unlikely to pick on a disposable box.

## 2. ⬜ `railway ssh --session` + Codex TUI rendering

- [ ] `railway ssh --session codex` attaches to the **same** tmux session ttyd is serving (not a
      second one) — the shared-session claim in the README depends on this.
- [ ] The Codex TUI renders correctly: box-drawing characters, 256 colours, no mojibake.
- [ ] Resizing the terminal reflows the TUI (SIGWINCH propagates through Railway's SSH transport).
- [ ] `TERM`, `LANG`, `LC_ALL` are what `/etc/profile.d/00-codex-env.sh` sets, verified with `env`
      inside an actual `railway ssh` shell.
- [ ] Pre-installed tmux is used rather than Railway trying to install its own.
- [x] ~~Attach-or-create doesn't produce two sessions~~ — verified locally; the entrypoint now
      starts session `codex` detached at boot so neither door has to create it.

**Fallback if broken:** if `--session` doesn't share the session, document the browser and SSH doors
as independent sessions and drop the "same session" claim.

## 3. ⬜ `codex login --device-auth` end-to-end through ttyd

- [ ] Opening the public domain prompts for basic auth and then lands in the tmux session.
- [ ] `codex login --device-auth` runs in the browser terminal, prints a readable code + URL, and
      does not hang trying to open a browser (the `xdg-open` shim should cover this).
- [ ] Approving at chatgpt.com completes the login; `codex login status` reports authenticated.
- [ ] The credential lands in `$CODEX_HOME/auth.json` on the **volume** — not an OS keyring.
      `cli_auth_credentials_store = "file"` is now set explicitly for this reason; confirm it
      actually takes effect after a real login.
- [ ] Repeat from a phone browser — this is the reason the browser door exists.

**Fallback if broken:** document the API-key path as primary and device-auth as best-effort.

## 4. ⬜ `codex resume` after a redeploy

- [ ] Start a session, redeploy the service, reconnect: `codex resume` lists the prior session and
      restores it.
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

## Cold-start checklist (run after the four above)

- [ ] `railway ssh --session codex` connects and lands in `/workspace/repos`.
- [ ] `codex --version` matches `ARG CODEX_VERSION`.
- [ ] `codex exec "hello"` returns a model response.
- [ ] `git clone` into `/workspace/repos` succeeds and survives a redeploy.
- [ ] Browser terminal basic auth rejects a wrong password.
- [ ] With `OPENAI_API_KEY` set *and* an existing device-auth login, boot logs say the existing
      login was left alone.
