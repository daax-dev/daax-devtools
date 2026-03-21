#!/usr/bin/env bash
# Build and push daax-agents devcontainer images to Docker Hub
# Builds for both linux/amd64 and linux/arm64 architectures
#
# 2-PHASE BUILD ARCHITECTURE:
#   Phase 1 (Base): daax-agents-base - Stable system dependencies
#                   Python, Node, Go, uv, pnpm, dev tools, oh-my-posh
#                   Changes infrequently (~monthly)
#
#   Phase 2 (Tools): daax-agents - AI coding CLIs on top of base
#                    Claude Code, Copilot, Codex, Gemini, backlog.md
#                    Changes frequently (~weekly when tools update)
#
# Prerequisites:
#   docker login          # Docker Hub credentials
#   docker login dhi.io   # DHI uses same Docker Hub credentials
#
# Usage:
#   ./build-push-docker.sh                    # Build and push tools only (uses cached base)
#   ./build-push-docker.sh --base             # Rebuild base layer first
#   ./build-push-docker.sh --base-only        # Only rebuild base layer
#   ./build-push-docker.sh v1.2.3             # Build and push with version tag
#   ./build-push-docker.sh --base v1.2.3      # Full rebuild with version tag

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_IMAGE_NAME="jpoley/daax-agents-base"
TOOLS_IMAGE_NAME="jpoley/daax-agents"
PLATFORMS="linux/amd64,linux/arm64"

# Parse arguments
BUILD_BASE=false
BASE_ONLY=false
VERSION_TAG=""

# Validate version tag to prevent shell injection
# Only allow: v, digits, dots, hyphens (e.g., v1.2.3, v1.2.3-rc1)
validate_version_tag() {
    local tag="$1"
    if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
        echo "ERROR: Invalid version tag format: $tag" >&2
        echo "Version tag must match: vX.Y.Z or vX.Y.Z-suffix (e.g., v1.2.3, v1.2.3-rc1)" >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base)
            BUILD_BASE=true
            shift
            ;;
        --base-only)
            BUILD_BASE=true
            BASE_ONLY=true
            shift
            ;;
        v*)
            VERSION_TAG="$1"
            validate_version_tag "$VERSION_TAG"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--base] [--base-only] [vX.Y.Z]"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}==>${NC} $*"; }
error() { echo -e "${RED}==>${NC} $*" >&2; }
section() { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }

# Check Docker is running
if ! docker info &>/dev/null; then
    error "Docker is not running. Please start Docker Desktop."
    exit 1
fi

# Check Docker Hub login by looking for auth entry in config
if ! grep -q "index.docker.io" ~/.docker/config.json 2>/dev/null; then
    warn "Not logged in to Docker Hub. Run: docker login"
    exit 1
fi
info "Docker Hub credentials found"

# Check DHI login
if ! grep -q "dhi.io" ~/.docker/config.json 2>/dev/null; then
    error "Not logged in to DHI. Run: docker login dhi.io"
    error "(Use your Docker Hub credentials)"
    exit 1
fi
info "DHI credentials found"

# Ensure buildx builder exists with multi-platform support
BUILDER_NAME="daax-multiplatform"
if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
    info "Creating buildx builder: $BUILDER_NAME"
    docker buildx create --name "$BUILDER_NAME" --driver docker-container --bootstrap
fi
docker buildx use "$BUILDER_NAME"

# Build base layer if requested
if [[ "$BUILD_BASE" == "true" ]]; then
    section "Phase 1: Building BASE layer"

    BASE_TAGS="--tag ${BASE_IMAGE_NAME}:latest"
    if [[ -n "$VERSION_TAG" ]]; then
        VERSION="${VERSION_TAG#v}"
        BASE_TAGS="$BASE_TAGS --tag ${BASE_IMAGE_NAME}:${VERSION}"
        info "Building base with tags: latest, ${VERSION}"
    else
        info "Building base with tag: latest"
    fi

    info "Building for platforms: $PLATFORMS"
    info "This may take 5-10 minutes..."

    docker buildx build \
        --platform "$PLATFORMS" \
        $BASE_TAGS \
        --push \
        --progress=plain \
        -f "$SCRIPT_DIR/Dockerfile.base" \
        "$SCRIPT_DIR"

    info "Successfully pushed ${BASE_IMAGE_NAME}"

    if [[ "$BASE_ONLY" == "true" ]]; then
        echo ""
        echo "Base layer build complete. Skipping tools layer (--base-only)."
        echo "Verify with:"
        echo "  docker pull ${BASE_IMAGE_NAME}:latest"
        echo "  docker run --rm ${BASE_IMAGE_NAME}:latest zsh -c 'uv --version && node --version'"
        exit 0
    fi
fi

# Build tools layer
section "Phase 2: Building TOOLS layer"

TOOLS_TAGS="--tag ${TOOLS_IMAGE_NAME}:latest"
if [[ -n "$VERSION_TAG" ]]; then
    VERSION="${VERSION_TAG#v}"
    TOOLS_TAGS="$TOOLS_TAGS --tag ${TOOLS_IMAGE_NAME}:${VERSION}"
    info "Building tools with tags: latest, ${VERSION}"
else
    info "Building tools with tag: latest"
fi

info "Building for platforms: $PLATFORMS"
info "This may take 2-5 minutes (using cached base layer)..."

docker buildx build \
    --platform "$PLATFORMS" \
    $TOOLS_TAGS \
    --push \
    --progress=plain \
    "$SCRIPT_DIR"

info "Successfully pushed ${TOOLS_IMAGE_NAME}"

echo ""
section "Build Complete"
echo ""
echo "Verify with:"
echo "  docker pull ${TOOLS_IMAGE_NAME}:latest"
echo "  docker run --rm ${TOOLS_IMAGE_NAME}:latest zsh -c 'claude --version && (copilot --version 2>&1 || echo \"copilot not installed\")'"
echo ""
echo "Image architecture:"
echo "  Base layer:  ${BASE_IMAGE_NAME}:latest  (stable - rebuild monthly)"
echo "  Tools layer: ${TOOLS_IMAGE_NAME}:latest (AI CLIs - rebuild weekly)"
