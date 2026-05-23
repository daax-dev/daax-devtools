# Daax Lean Development Container
# Minimal image: Claude Code + Flowspec only
# No Go toolchain in the final image (fzf is built in a throwaway golang stage
# and only its static binary is copied in), keeping the Go CVE surface at zero.
#
# Build: docker build -t daax-lean -f .devcontainer/lean/Dockerfile .devcontainer

# fzf builder stage — build with a current Go toolchain to avoid the outdated
# golang/stdlib CVEs shipped in Alpine's apk fzf and the upstream release binary.
# buildx runs this stage per target platform, so GOARCH matches automatically.
FROM golang:1.26-alpine AS fzf-builder
ARG FZF_VERSION=0.73.0
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
ARG GH_VERSION=2.92.0
ARG GH_SHA256_AMD64=b57848131bdf0c229cd35e1f2a51aa718199858b2e728410b37e89a428943ec4
ARG GH_SHA256_ARM64=c2248526dd0160c08d3fccca2332c3c1a07c15a78b23978e77735f1b5a18cfee
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
# Checksums for musl libc tarballs from uv 0.11.16 release assets:
#   - linux/amd64: uv-x86_64-unknown-linux-musl.tar.gz
#   - linux/arm64: uv-aarch64-unknown-linux-musl.tar.gz
# See: https://github.com/astral-sh/uv/releases/download/0.11.16/
ARG UV_VERSION=0.11.16
ARG UV_SHA256_AMD64=1bc4be1be0a000f893b0d1db97906cf392b63fa22fda9a0ecf33d0d4bbb4bc9a
ARG UV_SHA256_ARM64=ac022d96411143b9a2dd75ea711fa8dd4cd14538bf248f2e5df3c10a80f7f6a4
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
RUN pnpm install -g --allow-build=@anthropic-ai/claude-code @anthropic-ai/claude-code \
    && timeout 15 claude --version

# Install task management
RUN pnpm install -g backlog.md || echo "backlog.md install skipped"

# Install flowspec
# flowspec is core to the lean image, so this must succeed (no silent skip).
# --no-cache: keeps flowspec's checked-out sbom.spdx out of build layers (syft
# would otherwise merge its entries into the image SBOM as phantom Go CVEs).
RUN /home/vscode/.local/bin/uv tool install --no-cache git+https://github.com/jpoley/flowspec.git@v0.4.004 \
    && flowspec --version

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
