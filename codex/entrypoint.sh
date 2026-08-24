#!/bin/bash
set -e

# ════════════════════════════════════════════════════════════
# Codex box — boot script
#
# Goal: typing `codex` here should feel exactly like typing `codex` on your
# laptop — same TUI, same sessions, same auth — except the box lives in the
# cloud and keeps working when your machine sleeps.
#
# Two doors into the SAME container:
#   • railway ssh --session codex   → tmux session "codex"
#   • the public Railway domain     → ttyd, attached to that same session
#
# Everything persistent lives on the /workspace volume.
# ════════════════════════════════════════════════════════════

# ── Volume layout ───────────────────────────────────────────
mkdir -p /workspace/codex \
         /workspace/repos \
         /workspace/.ssh \
         /workspace/logs
chmod 700 /workspace/.ssh

# Codex keeps *everything* under one directory: auth.json, config.toml,
# sessions/, history.jsonl, skills/, plugins/ and its SQLite state. Point
# CODEX_HOME at the volume so `codex resume` still lists your sessions after a
# redeploy.
#
# Belt and braces: also symlink ~/.codex, so anything that hardcodes the default
# path (or a shell where CODEX_HOME didn't get exported) still lands on the
# volume. A naive `ln` would drop the link *inside* an existing real directory,
# leaving auth.json on the ephemeral container layer — so remove a real dir
# first. (That path lives in the image layer, never on the volume.)
export CODEX_HOME=/workspace/codex
[ -L /root/.codex ] || rm -rf /root/.codex
ln -sfn /workspace/codex /root/.codex
ln -sfn /workspace/.ssh  /root/.ssh

# Seed the default config on first boot only — never clobber user edits.
# approval_policy comes from CODEX_APPROVAL_POLICY so deployers can choose their
# posture in Railway Variables without SSHing in. Codex 0.149.x accepts exactly
# two values; anything else would make Codex fail to start, so validate here
# rather than shipping a box that won't boot.
CODEX_APPROVAL_POLICY="${CODEX_APPROVAL_POLICY:-on-request}"
case "$CODEX_APPROVAL_POLICY" in
    on-request|never) ;;
    *)
        echo "[boot] WARNING: CODEX_APPROVAL_POLICY='${CODEX_APPROVAL_POLICY}' is not valid"
        echo "[boot]          (expected 'on-request' or 'never') — falling back to 'on-request'."
        CODEX_APPROVAL_POLICY="on-request"
        ;;
esac

if [ ! -f "$CODEX_HOME/config.toml" ]; then
    echo "[boot] seeding $CODEX_HOME/config.toml (first boot, approval_policy=${CODEX_APPROVAL_POLICY})..."
    sed "s/^approval_policy = .*/approval_policy = \"${CODEX_APPROVAL_POLICY}\"/" \
        /opt/codex/config.toml.default > "$CODEX_HOME/config.toml"
else
    CURRENT_POLICY="$(grep -m1 '^approval_policy' "$CODEX_HOME/config.toml" || echo 'unset')"
    echo "[boot] existing config.toml kept (${CURRENT_POLICY})."
fi

# ── Prune volume churn ──────────────────────────────────────
# shell_snapshots/: Codex dumps every exported environment variable to disk here
# (`declare -xp`, excluding only PWD/OLDPWD). On Railway that means your service
# variables — API keys, tokens, the web password — written in plaintext onto the
# volume. They're never reused across runs and Codex GCs them after 3 days, so
# there is no reason to carry them across a redeploy.
#
# packages/: retained standalone release archives. Unused on an npm install like
# ours, but it has no GC and can reach ~1 GB if the updater ever populates it.
rm -rf "$CODEX_HOME/shell_snapshots" "$CODEX_HOME/packages"

# ── Git / SSH bootstrap ─────────────────────────────────────
# Generate an ed25519 key on first boot (persists via the volume).
if [ ! -f /workspace/.ssh/id_ed25519 ]; then
    echo "[boot] generating ed25519 git key (first boot)..."
    ssh-keygen -t ed25519 -C "codex-box@$(hostname)" \
        -f /workspace/.ssh/id_ed25519 -N "" -q
fi
chmod 600 /workspace/.ssh/id_ed25519 2>/dev/null || true
chmod 644 /workspace/.ssh/id_ed25519.pub 2>/dev/null || true

if ! grep -q "^github.com" /workspace/.ssh/known_hosts 2>/dev/null; then
    echo "[boot] trusting github.com host keys..."
    ssh-keyscan -t rsa,ecdsa,ed25519 github.com 2>/dev/null \
        >> /workspace/.ssh/known_hosts || true
    chmod 644 /workspace/.ssh/known_hosts
fi

git config --global init.defaultBranch main 2>/dev/null || true
[ -n "$GIT_USER_EMAIL" ] && git config --global user.email "$GIT_USER_EMAIL" 2>/dev/null || true
[ -n "$GIT_USER_NAME" ]  && git config --global user.name  "$GIT_USER_NAME"  2>/dev/null || true

# gh auth — re-run each boot if GITHUB_TOKEN is provided.
if [ -n "$GITHUB_TOKEN" ] && command -v gh >/dev/null 2>&1; then
    if ! gh auth status >/dev/null 2>&1; then
        echo "[boot] authenticating gh CLI from GITHUB_TOKEN..."
        echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null \
            || echo "[boot] gh auth login failed (token may be invalid)"
    fi
fi

# ── Codex auth ──────────────────────────────────────────────
# Two supported paths, in order of preference for *your* wallet:
#
#   1. ChatGPT plan  → `codex login --device-auth` (interactive, one time).
#      Run it in the browser terminal or over SSH; it prints a short code you
#      approve at chatgpt.com from any device. Credentials land in
#      $CODEX_HOME/auth.json on the volume and survive redeploys.
#
#   2. API key       → set OPENAI_API_KEY in Railway Variables. Seeded below on
#      every boot if you are not already logged in. Bills at API rates, NOT
#      against a ChatGPT plan.
#
# Seeding is skipped when a login already exists, so an interactive device-auth
# login is never stomped by a leftover env var.
if [ -n "$OPENAI_API_KEY" ]; then
    if codex login status >/dev/null 2>&1; then
        echo "[boot] codex already authenticated — leaving existing login alone."
    else
        echo "[boot] seeding codex auth from OPENAI_API_KEY..."
        printenv OPENAI_API_KEY | codex login --with-api-key >/dev/null 2>&1 \
            && echo "[boot] codex login --with-api-key ok" \
            || echo "[boot] codex login --with-api-key failed (key may be invalid)"
    fi
else
    codex login status >/dev/null 2>&1 \
        && echo "[boot] codex authenticated (existing login on volume)." \
        || echo "[boot] codex NOT authenticated — run 'codex login --device-auth' in the terminal."
fi

# ── Browser terminal (ttyd) basic auth ──────────────────────
# ttyd is the container's main process, exposed on a PUBLIC Railway domain, and
# it hands out a writable shell — so it MUST be password-protected. Use a
# user-supplied password, or generate one on first boot and persist it on the
# volume (stable across redeploys). Username defaults to "codex".
export CODEX_WEB_USERNAME="${CODEX_WEB_USERNAME:-codex}"
if [ -z "$CODEX_WEB_PASSWORD" ]; then
    PWFILE=/workspace/.codex-web-password
    if [ ! -f "$PWFILE" ]; then
        head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-24 > "$PWFILE"
        chmod 600 "$PWFILE"
    fi
    export CODEX_WEB_PASSWORD="$(cat "$PWFILE")"
fi
echo "[boot] browser terminal auth → user: ${CODEX_WEB_USERNAME}  password: ${CODEX_WEB_PASSWORD}"

# ── Env into SSH / tmux login shells ────────────────────────
# `railway ssh` opens a login shell that does NOT inherit the service env, and
# tmux is configured to spawn login shells too. Mirror what Codex needs into
# /etc/profile.d so both doors behave identically.
echo "[boot] writing /etc/profile.d/00-codex-env.sh for login shells..."
{
    echo "# Auto-generated by entrypoint.sh on each boot."
    echo "export CODEX_HOME=/workspace/codex"
    echo "export TERM=\${TERM:-xterm-256color}"
    echo "export LANG=en_US.UTF-8"
    echo "export LC_ALL=en_US.UTF-8"
    for var in OPENAI_API_KEY CODEX_ACCESS_TOKEN GITHUB_TOKEN \
               CODEX_WEB_USERNAME CODEX_WEB_PASSWORD; do
        val="${!var:-}"
        [ -n "$val" ] && printf 'export %s=%q\n' "$var" "$val"
    done
    # Land in your repos directory on login.
    echo 'cd /workspace/repos 2>/dev/null || true'
} > /etc/profile.d/00-codex-env.sh
chmod 644 /etc/profile.d/00-codex-env.sh

# ── The shared tmux session ─────────────────────────────────
# Start it detached at boot so it always EXISTS before either door knocks.
# Otherwise the session is created by whoever connects first, and the two doors
# can race into separate sessions. Both ttyd and `railway ssh --session codex`
# use attach-or-create semantics, so they now reliably land in this one.
#
# Note this session is in-memory: a container restart starts it empty. That's
# fine — what you actually care about (Codex history) is on the volume, so
# `codex resume` picks the conversation back up.
if ! tmux has-session -t codex 2>/dev/null; then
    echo "[boot] starting detached tmux session 'codex'..."
    tmux new-session -d -s codex -c /workspace/repos
fi

echo "[boot] browser → public Railway domain.  terminal → railway ssh --session codex, then 'codex'."
exec "$@"
