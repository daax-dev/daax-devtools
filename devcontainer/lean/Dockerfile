# Daax Lean Development Container
# Minimal image: Claude Code + Flowspec only
# No Go toolchain in the final image (fzf is built in a throwaway golang stage
# and only its static binary is copied in), keeping the Go CVE surface at zero.
# Includes Herdr for terminal-native multi-agent session management.
#
# Build: docker build -t daax-lean -f .devcontainer/lean/Dockerfile .devcontainer

# fzf builder stage — build with a current Go toolchain to avoid the outdated
# golang/stdlib CVEs shipped in Alpine's apk fzf and the upstream release binary.
# buildx runs this stage per target platform, so GOARCH matches automatically.
FROM golang:1.26-alpine AS fzf-builder
ARG FZF_VERSION=0.73.1
ENV CGO_ENABLED=0
RUN go install "github.com/junegunn/fzf@v${FZF_VERSION}" \
    && /go/bin/fzf --version

# Python 3.14: 3.13.x carries CVE-2026-6100 in CPython with no stable 3.13 fix
# (fixed in 3.14.5+). The 3.14 DHI base is 0-critical.
FROM dhi.io/python:3.14-alpine3.22-dev

# System dependencies (no Go)
# apk upgrade first to pull patched Alpine packages (e.g. openssl security fixes)
RUN apk upgrade --no-cache && apk add --no-cache \
    bash \
    curl \
    git \
    nodejs \
    npm \
    zsh \
    shadow \
    sudo \
    jq \
    tar \
    gzip \
    libc-utils \
    tmux

# Upgrade npm and install pnpm
RUN npm install -g npm@latest \
    && npm cache clean --force \
    && npm install -g pnpm

# Install GitHub CLI
# Version: 2.95.0 (2026-07) - Latest stable (embeds x/crypto 0.53.0, x/net 0.55.0)
ARG GH_VERSION=2.95.0
ARG GH_SHA256_AMD64=25d1e4729e8808c9ed3d613e96ebd3f3e44446f2d368c89d878a71a36ddb3d8c
ARG GH_SHA256_ARM64=d41e0b3b6218e5741c8bb4db39b16e53a59e0e06299a8489bd38f623ef7ebaae
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

# Install fzf — built from source with a current Go toolchain (see fzf-builder
# stage above). Static (CGO_ENABLED=0) so it runs on musl with no runtime libs.
COPY --from=fzf-builder /go/bin/fzf /usr/local/bin/fzf
RUN chmod +x /usr/local/bin/fzf && fzf --version

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
# Checksums for musl libc tarballs from uv 0.11.26 release assets:
#   - linux/amd64: uv-x86_64-unknown-linux-musl.tar.gz
#   - linux/arm64: uv-aarch64-unknown-linux-musl.tar.gz
# See: https://github.com/astral-sh/uv/releases/download/0.11.26/
ARG UV_VERSION=0.11.26
ARG UV_SHA256_AMD64=62bf1a53501adf4083224b69b33737450ac516935f5a5e483e9dfaf2665084de
ARG UV_SHA256_ARM64=47418cfdb34b1ca42e503da72631ac8c475602e2411ac6c39aa84c2373fe6324
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

# Install Claude Code CLI. --allow-build lets pnpm run claude-code's postinstall
# so the platform-native binary is fetched (pnpm v10+ blocks build scripts by
# default, otherwise shipping a non-functional `claude` shim).
# Pinned to the latest tag (2026-07-01) so a rebuild busts this layer and ships
# the current Claude Code rather than a cache-frozen older build.
RUN pnpm install -g --allow-build=@anthropic-ai/claude-code @anthropic-ai/claude-code@2.1.197 \
    && timeout 15 claude --version

# Install task management
RUN pnpm install -g backlog.md || echo "backlog.md install skipped"

# Install flowspec
# flowspec is core to the lean image, so this must succeed (no silent skip).
# --no-cache: keeps flowspec's checked-out sbom.spdx out of build layers (syft
# would otherwise merge its entries into the image SBOM as phantom Go CVEs).
# --build-constraints hatchling<1.27: flowspec's pyproject double-includes
# templates/.mcp.json (packages + a redundant force-include). hatchling >=1.27
# (uv's default Python 3.14 build env) rejects the duplicate; 1.26.x tolerates
# it. Build-time only. Durable fix is upstream in jpoley/flowspec.
RUN printf 'hatchling<1.27\n' > /tmp/flowspec-build-constraints.txt \
    && /home/vscode/.local/bin/uv tool install --no-cache --build-constraints /tmp/flowspec-build-constraints.txt git+https://github.com/jpoley/flowspec.git@v0.4.004 \
    && flowspec --version \
    && rm -f /tmp/flowspec-build-constraints.txt

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

# Install Herdr from the official static Linux release binary. The same binary
# runs on Alpine/musl because upstream ships it as static PIE.
USER root
ARG HERDR_VERSION=0.7.1
ARG HERDR_SHA256_AMD64=b965acaffc2c22f54b6e6c64af7cf8e98a3f4ac2622630a0599c67a4b9d8a654
ARG HERDR_SHA256_ARM64=3d757ac30c631e79dc45038c3ecc6423fe13a89f9cffa0f415aedd2c27f1576c
ENV HERDR_VERSION="${HERDR_VERSION}"
COPY install-herdr.sh /tmp/install-herdr.sh
COPY verify-herdr.sh /usr/local/bin/daax-verify-herdr
RUN chmod +x /tmp/install-herdr.sh /usr/local/bin/daax-verify-herdr \
    && /tmp/install-herdr.sh \
    && rm -f /tmp/install-herdr.sh
USER vscode

# Verify
RUN echo "=== Lean Image Verification ===" \
    && echo "Python: $(python --version)" \
    && echo "Node: $(node --version)" \
    && echo "pnpm: $(pnpm --version)" \
    && echo "uv: $(/home/vscode/.local/bin/uv --version)" \
    && echo "gh: $(gh --version | head -1)" \
    && echo "flowspec: $(flowspec --version 2>&1 || echo 'not installed')" \
    && echo "claude: $(claude --version 2>&1 || echo 'not installed')" \
    && echo "herdr: $(herdr --version 2>&1 || echo 'not installed')" \
    && daax-verify-herdr build

LABEL org.opencontainers.image.title="Daax Lean"
LABEL org.opencontainers.image.description="Minimal devcontainer: Claude Code + Flowspec + Herdr (no Go tools)"
LABEL ai.daax.variant="lean"
LABEL ai.daax.includes="claude-code,herdr,flowspec,backlog.md"
LABEL ai.daax.versions.herdr="0.7.1"

CMD ["zsh"]
