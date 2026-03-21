#!/bin/bash
# Rebuild the daax-code-server image with language runtimes
#
# Builds a custom code-server image that includes Go, Node.js, Python,
# Rust, and common build tools so the VS Code integrated terminal works
# out of the box.
#
# Usage:
#   ./rebuild-code-server.sh
#
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_NAME="daax-code-server"
TAG="${1:-latest}"

# Auto-detect host architecture so --build-arg TARGETARCH is always set.
# Dockerfile.code-server hard-fails when TARGETARCH is unset.
if [ -z "${TARGETARCH:-}" ]; then
  detected_arch="$(docker info --format '{{.Architecture}}' 2>/dev/null || uname -m)"
  case "$detected_arch" in
    x86_64|amd64)  TARGETARCH=amd64 ;;
    aarch64|arm64) TARGETARCH=arm64 ;;
    *)
      echo "ERROR: Unsupported architecture '$detected_arch'. Cannot determine TARGETARCH." >&2
      exit 1
      ;;
  esac
fi

echo "🔨 Building $IMAGE_NAME:$TAG (Go, Node, Python, Rust) for TARGETARCH=$TARGETARCH..."
docker build --build-arg TARGETARCH="$TARGETARCH" \
  -f devcontainer/Dockerfile.code-server -t "$IMAGE_NAME:$TAG" devcontainer

echo "✅ Built $IMAGE_NAME:$TAG"
echo ""
echo "To use: restart code-server container or run  docker compose up -d --no-build code-server"
