# Daax Lean Development Container
# Minimal image: Claude Code + Flowspec only
# No Go tools (gastown/beads) - eliminates CVE-2025-65637, CVE-2025-47913, CVE-2025-22869
#
# Build: docker build -t daax-lean -f .devcontainer/lean/Dockerfile .devcontainer

FROM dhi.io/python:3.13-alpine3.22-dev

# System dependencies (no Go)
RUN apk add --no-cache \
    bash \
    curl \
    nodejs \
    npm \
    zsh \
    shadow \
    sudo \
    jq \
    tar \
    gzip \
    libc-utils \
    tmux \
    fzf

# Upgrade npm and install pnpm
RUN npm install -g npm@latest \
    && npm cache clean --force \
    && npm install -g pnpm

# Install GitHub CLI
ARG GH_VERSION=2.87.2
ARG GH_SHA256_AMD64=18360b2243e3bf9c1457035db45f6400ae4cf957dcc2f674e69717b4e0b14d55
ARG GH_SHA256_ARM64=e37efdd8ec98425f44175040b5037c767bbd49f192aed1de5aabc4b4ea9e22c5
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
        "amd64") GH_ARCH="linux_amd64"; GH_SHA256="${GH_SHA256_AMD64}" ;; \
        "arm64") GH_ARCH="linux_arm64"; GH_SHA256="${GH_SHA256_ARM64}" ;; \
        *) echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && curl -sL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_${GH_ARCH}.tar.gz" -o /tmp/gh.tar.gz \
    && echo "${GH_SHA256}  /tmp/gh.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && mv "/tmp/gh_${GH_VERSION}_${GH_ARCH}/bin/gh" /usr/local/bin/gh \
    && chmod +x /usr/local/bin/gh \
    && rm -rf /tmp/gh*

# Create vscode user
RUN addgroup -g 1000 vscode \
    && adduser -u 1000 -G vscode -h /home/vscode -s /bin/zsh -D vscode \
    && echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

USER vscode
WORKDIR /home/vscode

# Environment
ENV PNPM_HOME="/home/vscode/.local/share/pnpm"
ENV PATH="/home/vscode/.local/bin:${PNPM_HOME}:/usr/local/bin:${PATH}"

# Install uv (Python package manager) with SHA256 checksum verification
# Checksums for musl libc tarballs from uv 0.10.4 release assets:
#   - linux/amd64: uv-x86_64-unknown-linux-musl.tar.gz
#   - linux/arm64: uv-aarch64-unknown-linux-musl.tar.gz
# See: https://github.com/astral-sh/uv/releases/download/0.10.4/
ARG UV_VERSION=0.10.4
ARG UV_SHA256_AMD64=18adf097cea30a165ba086c1e72659fec3c5aca056a560e7c39e0164ac871196
ARG UV_SHA256_ARM64=82fc461031dafb130af761e7dbec1bcc51b826c2e664f5bf8bc4e4f8330320cd
RUN mkdir -p /home/vscode/.local/bin \
    && case "${TARGETARCH}" in \
        "amd64") UV_ARCH="x86_64-unknown-linux-musl"; UV_SHA256="${UV_SHA256_AMD64}" ;; \
        "arm64") UV_ARCH="aarch64-unknown-linux-musl"; UV_SHA256="${UV_SHA256_ARM64}" ;; \
        *) echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && curl -sL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_ARCH}.tar.gz" -o /tmp/uv.tar.gz \
    && echo "${UV_SHA256}  /tmp/uv.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/uv.tar.gz --strip-components=1 -C /home/vscode/.local/bin \
    && rm -rf /tmp/uv*

# Configure pnpm
RUN mkdir -p "$PNPM_HOME" && pnpm config set global-bin-dir "$PNPM_HOME"

# Install Claude Code CLI only
RUN pnpm install -g @anthropic-ai/claude-code || echo "Claude Code install deferred to postCreate"

# Install task management
RUN pnpm install -g backlog.md || echo "backlog.md install skipped"

# Install flowspec
RUN /home/vscode/.local/bin/uv tool install git+https://github.com/jpoley/flowspec.git@v0.4.004 || echo "flowspec install skipped"

# Python tools
RUN /home/vscode/.local/bin/uv tool install ruff \
    && /home/vscode/.local/bin/uv tool install pytest

# Shell config
RUN echo 'export PNPM_HOME="/home/vscode/.local/share/pnpm"' > /home/vscode/.zshenv \
    && echo 'export PATH="/home/vscode/.local/bin:$PNPM_HOME:/usr/local/bin:$PATH"' >> /home/vscode/.zshenv

# Cleanup
RUN /home/vscode/.local/bin/uv cache clean \
    && pnpm store prune 2>/dev/null || true \
    && npm cache clean --force 2>/dev/null || true \
    && rm -rf /tmp/* 2>/dev/null || true

# Verify
RUN echo "=== Lean Image Verification ===" \
    && echo "Python: $(python --version)" \
    && echo "Node: $(node --version)" \
    && echo "pnpm: $(pnpm --version)" \
    && echo "uv: $(/home/vscode/.local/bin/uv --version)" \
    && echo "gh: $(gh --version | head -1)" \
    && echo "flowspec: $(flowspec --version 2>&1 || echo 'not installed')" \
    && echo "claude: $(claude --version 2>&1 || echo 'not installed')"

LABEL org.opencontainers.image.title="Daax Lean"
LABEL org.opencontainers.image.description="Minimal devcontainer: Claude Code + Flowspec (no Go tools)"

CMD ["zsh"]
