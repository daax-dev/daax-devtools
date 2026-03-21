#!/bin/bash
# Daax Devcontainer Prebuild Script
#
# This script builds a complete devcontainer image with all features baked in,
# eliminating the need to apply features at container startup time.
#
# Usage:
#   ./prebuild.sh              # Build only
#   ./prebuild.sh --push       # Build and push to Docker Hub
#   ./prebuild.sh --no-cache   # Build without cache
#
# The resulting image can be used directly in devcontainer.json:
#   "image": "jpoley/daax-devcontainer:latest"
#
# Prerequisites:
#   - devcontainer CLI: npm install -g @devcontainers/cli
#   - Docker logged in (for push): docker login
#

set -e

# Configuration
IMAGE_NAME="${DEVCONTAINER_IMAGE:-jpoley/daax-devcontainer}"
IMAGE_TAG="${DEVCONTAINER_TAG:-latest}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# Parse arguments
PUSH=false
NO_CACHE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH=true
            shift
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --tag)
            IMAGE_TAG="$2"
            FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--push] [--no-cache] [--tag TAG]"
            exit 1
            ;;
    esac
done

# Get script directory (where devcontainer.json lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo "Daax Devcontainer Prebuild"
echo "========================================"
echo ""
echo "Workspace:  $WORKSPACE_DIR"
echo "Image:      $FULL_IMAGE"
echo "Push:       $PUSH"
echo "No-cache:   ${NO_CACHE:-false}"
echo ""

# Check for devcontainer CLI
if ! command -v devcontainer &> /dev/null; then
    echo "Error: devcontainer CLI not found"
    echo "Install with: npm install -g @devcontainers/cli"
    exit 1
fi

# Build the devcontainer image with features baked in
echo "Building devcontainer image..."
echo ""

BUILD_ARGS=(
    build
    --workspace-folder "$WORKSPACE_DIR"
    --image-name "$FULL_IMAGE"
)

if [ -n "$NO_CACHE" ]; then
    BUILD_ARGS+=(--no-cache)
fi

if [ "$PUSH" = true ]; then
    BUILD_ARGS+=(--push)
fi

devcontainer "${BUILD_ARGS[@]}"

echo ""
echo "========================================"
echo "Build Complete!"
echo "========================================"
echo ""
echo "Image: $FULL_IMAGE"
echo ""

if [ "$PUSH" = true ]; then
    echo "Image pushed to registry."
    echo ""
    echo "To use the prebuilt image, update devcontainer.json:"
    echo '  "image": "'"$FULL_IMAGE"'"'
    echo ""
    echo "And remove or comment out the 'features' section since they're baked in."
else
    echo "To push the image:"
    echo "  docker push $FULL_IMAGE"
    echo ""
    echo "Or rebuild with --push:"
    echo "  $0 --push"
fi
echo ""
