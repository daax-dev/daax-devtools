#!/bin/bash
# Push daax-agents devcontainer image to Docker Hub
#
# This script builds and pushes the AI agents devcontainer image.
# Used by daax-cli and daax-web for AI coding sessions.
#
# Usage:
#   ./push.sh              # Push to Docker Hub with :latest tag
#   ./push.sh --tag v1.0.0 # Push with specific version tag
#
# Prerequisites:
#   - Docker Buildx installed (for multi-arch builds)
#   - Logged in to Docker Hub: docker login

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

# Defaults
DOCKERHUB_REGISTRY="docker.io"
AGENTS_IMAGE="jpoley/daax-agents"
TAG="latest"
PLATFORMS="linux/amd64"  # Add linux/arm64 if needed

show_help() {
    head -12 "$0" | grep -E '^#' | sed 's/^# //' | sed 's/^#//'
    exit 0
}

check_buildx() {
    if ! docker buildx version &> /dev/null; then
        error "Docker Buildx not found. Install with: docker buildx install"
        exit 1
    fi
}

check_auth() {
    local registry="$1"
    local index_configs
    if index_configs="$(docker info --format '{{json .RegistryConfig.IndexConfigs}}' 2>/dev/null)"; then
        if ! grep -q "\"${registry}\"" <<< "${index_configs}"; then
            warn "Could not confirm authentication to Docker Hub. Ensure you are logged in with: docker login"
        fi
    else
        warn "Unable to query Docker info; cannot verify authentication for ${registry}."
    fi
    return 0
}

setup_builder() {
    local builder_name="daax-builder"

    if ! docker buildx inspect "$builder_name" &> /dev/null; then
        log "Creating buildx builder: $builder_name"
        docker buildx create --name "$builder_name" --driver docker-container --bootstrap
    fi

    docker buildx use "$builder_name"
    success "Using builder: $builder_name"
}

push_agents_image() {
    log "Building and pushing agents image..."
    log "  Registry: ${DOCKERHUB_REGISTRY}/${AGENTS_IMAGE}"
    log "  Tag: ${TAG}"
    log "  Platforms: ${PLATFORMS}"

    docker buildx build \
        --platform "${PLATFORMS}" \
        --tag "${DOCKERHUB_REGISTRY}/${AGENTS_IMAGE}:${TAG}" \
        --push \
        --cache-from "type=registry,ref=${DOCKERHUB_REGISTRY}/${AGENTS_IMAGE}:buildcache" \
        --cache-to "type=registry,ref=${DOCKERHUB_REGISTRY}/${AGENTS_IMAGE}:buildcache,mode=max" \
        --file devcontainer/Dockerfile \
        devcontainer

    success "Pushed ${DOCKERHUB_REGISTRY}/${AGENTS_IMAGE}:${TAG}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)
            if [[ $# -lt 2 ]]; then
                error "Missing value for --tag"
                echo "Use --help for usage information"
                exit 1
            fi
            TAG="$2"
            shift 2
            ;;
        --platforms)
            if [[ $# -lt 2 ]]; then
                error "Missing value for --platforms"
                echo "Use --help for usage information"
                exit 1
            fi
            PLATFORMS="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main execution
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     Daax Agents Image Push               ║"
echo "╚══════════════════════════════════════════╝"
echo ""

check_buildx
check_auth "$DOCKERHUB_REGISTRY"
setup_builder

push_agents_image

echo ""
success "Agents image pushed successfully!"
echo ""
