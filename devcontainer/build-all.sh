#!/usr/bin/env bash
# Build all daax-agents container variants
# Builds in dependency order: base -> core -> framework variants
#
# MODULAR CONTAINER ARCHITECTURE:
#   base     : System dependencies (Python, Node, Go, dev tools)
#   core     : AI coding CLIs only (Claude, Copilot, Codex, Gemini, OpenCode, Kiro)
#   flowspec : Core + flowspec + backlog.md
#   gsd      : Core + get-shit-done-cc
#   openspec : Core + @fission-ai/openspec
#
# Prerequisites:
#   docker login          # Docker Hub credentials (for --push)
#
# Usage:
#   ./build-all.sh                        # Build all variants locally
#   ./build-all.sh core                   # Build only core (and base if needed)
#   ./build-all.sh flowspec               # Build only flowspec (and dependencies)
#   ./build-all.sh base core flowspec     # Build specific variants
#   ./build-all.sh --no-cache all         # Rebuild without cache
#   ./build-all.sh --push all             # Build and push to Docker Hub
#   ./build-all.sh --push --no-cache core # Rebuild core and push
#
# Dependency Graph:
#   base
#     └── core
#           ├── flowspec
#           ├── gsd
#           └── openspec

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Image names
IMAGE_PREFIX="jpoley/daax-agents"
PLATFORMS="linux/amd64,linux/arm64"

# Variants and their Dockerfiles
declare -A DOCKERFILES=(
    [base]="Dockerfile.base"
    [core]="Dockerfile.core"
    [flowspec]="Dockerfile.flowspec"
    [gsd]="Dockerfile.gsd"
    [openspec]="Dockerfile.openspec"
)

# Variant dependencies (parent -> children inherit from parent)
declare -A DEPENDENCIES=(
    [base]=""
    [core]="base"
    [flowspec]="core"
    [gsd]="core"
    [openspec]="core"
)

# Parse arguments
NO_CACHE=""
PUSH=""
VARIANTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --push)
            PUSH="true"
            shift
            ;;
        all)
            VARIANTS=(base core flowspec gsd openspec)
            shift
            ;;
        base|core|flowspec|gsd|openspec)
            VARIANTS+=("$1")
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options] [variants...]"
            echo ""
            echo "Options:"
            echo "  --no-cache    Build without using cache"
            echo "  --push        Push images to Docker Hub after building"
            echo "  -h, --help    Show this help message"
            echo ""
            echo "Variants:"
            echo "  base          System dependencies (Python, Node, Go)"
            echo "  core          AI coding CLIs (Claude, Copilot, Codex, etc.)"
            echo "  flowspec      Core + flowspec + backlog.md"
            echo "  gsd           Core + get-shit-done-cc"
            echo "  openspec      Core + @fission-ai/openspec"
            echo "  all           Build all variants"
            echo ""
            echo "Examples:"
            echo "  $0                        # Build all variants locally"
            echo "  $0 core                   # Build core (and base if needed)"
            echo "  $0 --push all             # Build and push all variants"
            echo "  $0 --no-cache flowspec    # Rebuild flowspec without cache"
            exit 0
            ;;
        *)
            echo "Unknown option or variant: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Default to all variants if none specified
if [[ ${#VARIANTS[@]} -eq 0 ]]; then
    VARIANTS=(base core flowspec gsd openspec)
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}==>${NC} $*"; }
error() { echo -e "${RED}==>${NC} $*" >&2; }
section() { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }
highlight() { echo -e "${CYAN}$*${NC}"; }

# Check Docker is running
if ! docker info &>/dev/null; then
    error "Docker is not running. Please start Docker Desktop."
    exit 1
fi

# If pushing, check Docker Hub login
if [[ "$PUSH" == "true" ]]; then
    if ! grep -q "index.docker.io" ~/.docker/config.json 2>/dev/null; then
        warn "Not logged in to Docker Hub. Run: docker login"
        exit 1
    fi
    info "Docker Hub credentials found"
fi

# Resolve dependencies - add required parent variants
resolve_dependencies() {
    local variant="$1"
    local dep="${DEPENDENCIES[$variant]}"

    if [[ -n "$dep" ]] && ! echo "${VARIANTS[@]}" | grep -qw -- "$dep"; then
        # Check if dependency image exists locally or remotely
        local dep_image="${IMAGE_PREFIX}-${dep}:latest"
        if ! docker image inspect "$dep_image" &>/dev/null; then
            if [[ "$PUSH" == "true" ]] && docker pull "$dep_image" &>/dev/null; then
                info "Pulled existing $dep_image from registry"
            else
                warn "Dependency '$dep' not found, adding to build list"
                VARIANTS=("$dep" "${VARIANTS[@]}")
                resolve_dependencies "$dep"
            fi
        fi
    fi
}

# Resolve all dependencies
ORIGINAL_VARIANTS=("${VARIANTS[@]}")
for variant in "${ORIGINAL_VARIANTS[@]}"; do
    resolve_dependencies "$variant"
done

# Remove duplicates while preserving order
UNIQUE_VARIANTS=()
for variant in "${VARIANTS[@]}"; do
    if ! echo "${UNIQUE_VARIANTS[@]:-}" | grep -qw -- "$variant"; then
        UNIQUE_VARIANTS+=("$variant")
    fi
done
VARIANTS=("${UNIQUE_VARIANTS[@]}")

# Sort by dependency order (base first, then core, then frameworks)
ORDERED_VARIANTS=()
for v in base core flowspec gsd openspec; do
    if echo "${VARIANTS[@]}" | grep -qw -- "$v"; then
        ORDERED_VARIANTS+=("$v")
    fi
done
VARIANTS=("${ORDERED_VARIANTS[@]}")

section "Build Plan"
echo ""
highlight "Variants to build: ${VARIANTS[*]}"
echo ""
echo "Build order (dependencies first):"
for i in "${!VARIANTS[@]}"; do
    variant="${VARIANTS[$i]}"
    dockerfile="${DOCKERFILES[$variant]}"
    image="${IMAGE_PREFIX}-${variant}:latest"
    # Handle base image name (no suffix)
    [[ "$variant" == "base" ]] && image="${IMAGE_PREFIX}-base:latest"
    echo "  $((i+1)). $variant -> $image"
done
echo ""

if [[ -n "$NO_CACHE" ]]; then
    warn "Building without cache (--no-cache)"
fi

if [[ "$PUSH" == "true" ]]; then
    info "Will push images to Docker Hub after building"

    # Ensure buildx builder exists with multi-platform support
    BUILDER_NAME="daax-multiplatform"
    if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
        info "Creating buildx builder: $BUILDER_NAME"
        docker buildx create --name "$BUILDER_NAME" --driver docker-container --bootstrap
    fi
    docker buildx use "$BUILDER_NAME"
fi

# Track build results
declare -A BUILD_RESULTS

# Build each variant
for variant in "${VARIANTS[@]}"; do
    section "Building: $variant"

    dockerfile="${DOCKERFILES[$variant]}"
    image="${IMAGE_PREFIX}-${variant}:latest"
    # Handle base image name (no suffix for compatibility)
    [[ "$variant" == "base" ]] && image="${IMAGE_PREFIX}-base:latest"

    info "Dockerfile: $dockerfile"
    info "Image: $image"

    if [[ "$PUSH" == "true" ]]; then
        # Multi-platform build and push
        info "Building for platforms: $PLATFORMS"

        if docker buildx build \
            --platform "$PLATFORMS" \
            --tag "$image" \
            $NO_CACHE \
            --push \
            --progress=plain \
            -f "$SCRIPT_DIR/$dockerfile" \
            "$SCRIPT_DIR"; then
            BUILD_RESULTS[$variant]="success"
            info "Successfully built and pushed: $image"
        else
            BUILD_RESULTS[$variant]="failed"
            error "Failed to build: $variant"
            exit 1
        fi
    else
        # Local build only (single platform)
        if docker build \
            --tag "$image" \
            $NO_CACHE \
            --progress=plain \
            -f "$SCRIPT_DIR/$dockerfile" \
            "$SCRIPT_DIR"; then
            BUILD_RESULTS[$variant]="success"
            info "Successfully built: $image"
        else
            BUILD_RESULTS[$variant]="failed"
            error "Failed to build: $variant"
            exit 1
        fi
    fi
done

# Summary
section "Build Summary"
echo ""
for variant in "${VARIANTS[@]}"; do
    result="${BUILD_RESULTS[$variant]}"
    image="${IMAGE_PREFIX}-${variant}:latest"
    [[ "$variant" == "base" ]] && image="${IMAGE_PREFIX}-base:latest"

    if [[ "$result" == "success" ]]; then
        echo -e "  ${GREEN}✓${NC} $variant -> $image"
    else
        echo -e "  ${RED}✗${NC} $variant -> $image"
    fi
done
echo ""

if [[ "$PUSH" == "true" ]]; then
    echo "Images pushed to Docker Hub. Verify with:"
    for variant in "${VARIANTS[@]}"; do
        image="${IMAGE_PREFIX}-${variant}:latest"
        [[ "$variant" == "base" ]] && image="${IMAGE_PREFIX}-base:latest"
        echo "  docker pull $image"
    done
else
    echo "Images built locally. To push to Docker Hub, run:"
    echo "  $0 --push ${VARIANTS[*]}"
fi
echo ""

# Print variant usage examples
section "Usage Examples"
echo ""
echo "Run a specific variant:"
for variant in "${VARIANTS[@]}"; do
    image="${IMAGE_PREFIX}-${variant}:latest"
    [[ "$variant" == "base" ]] && image="${IMAGE_PREFIX}-base:latest"
    echo "  docker run --rm -it $image zsh"
done
echo ""
echo "Use in devcontainer.json:"
echo '  { "image": "jpoley/daax-agents-flowspec:latest" }'
