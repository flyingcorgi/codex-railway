FROM node:20-slim

# Pin the Codex CLI. Codex ships several releases a week; an unpinned build means
# two deploys of the same commit can produce different agents. Bump deliberately.
ARG CODEX_VERSION=0.149.1
# ttyd — static single-binary web terminal (not packaged in Debian).
ARG TTYD_VERSION=1.7.7

# Tools a coding-agent box needs: git (clone/commit), gh (PRs/issues),
# openssh-client (git over SSH), curl/ca-certs/gnupg (installers & TLS),
# tmux (sessions that survive a dropped connection), bubblewrap (Codex's Linux
# sandbox), locales (UTF-8 box-drawing in the TUI), less/ripgrep (agent quality
# of life).
RUN apt-get update && apt-get install -y --no-install-recommends \
        git openssh-client ca-certificates curl gnupg \
        tmux bubblewrap locales less ripgrep procps \
    && rm -rf /var/lib/apt/lists/*

# The Codex TUI is a ratatui app: without a UTF-8 locale its box-drawing
# characters degrade to mojibake.
RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TERM=xterm-256color

# GitHub CLI — so the agent can `gh pr create`, `gh issue`, etc.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod 644 /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# ttyd — serves the browser terminal on the public Railway domain.
# Upstream publishes per-arch static binaries; map Debian arch names to theirs.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) TTYD_ARCH=x86_64 ;; \
        arm64) TTYD_ARCH=aarch64 ;; \
        *) echo "unsupported arch: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}" \
        -o /usr/local/bin/ttyd; \
    chmod +x /usr/local/bin/ttyd; \
    ttyd --version

# Codex CLI — OpenAI's coding agent. The npm package is a thin shim that pulls
# the per-arch native binary via optionalDependencies.
RUN npm install -g "@openai/codex@${CODEX_VERSION}" \
    && codex --version

# `codex login --device-auth` may try to open a browser via xdg-open; on a
# headless container that throws a noisy (harmless) error. Shim it to a no-op so
# the device code stays readable.
RUN printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/xdg-open \
    && chmod +x /usr/local/bin/xdg-open

# Default Codex config, seeded onto the volume on first boot only (never
# overwrites your edits). See entrypoint.sh.
COPY config.toml.default /opt/codex/config.toml.default
# tmux defaults: login shells (so /etc/profile.d is sourced) + mouse support,
# which makes the browser terminal usable for scrolling and pane selection.
COPY tmux.conf /root/.tmux.conf

WORKDIR /workspace
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ttyd listens here; Railway maps the public domain to $PORT.
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# Main process = ttyd serving a tmux session on the public Railway domain
# (basic-auth protected). `tmux new -A -s codex` attaches to the existing
# session if there is one, so closing the browser tab never kills your work —
# and `railway ssh --session codex` lands you in that *same* session.
CMD ["bash", "-lc", "exec ttyd --port ${PORT:-8080} --writable --credential \"${CODEX_WEB_USERNAME}:${CODEX_WEB_PASSWORD}\" -t fontSize=14 -t 'titleFixed=codex @ railway' tmux new -A -s codex"]
