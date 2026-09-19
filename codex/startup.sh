#!/bin/bash
# Wrapper to start both SSH and ttyd properly

# Start SSH daemon in background
/usr/sbin/sshd -D &
SSHD_PID=$!

# Start ttyd (the main process)
exec ttyd --port ${PORT:-8080} --writable --credential "${CODEX_WEB_USERNAME}:${CODEX_WEB_PASSWORD}" -t fontSize=14 -t macOptionClickForcesSelection=true -t 'titleFixed=codex @ railway' tmux new -A -s codex

