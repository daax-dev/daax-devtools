#!/bin/bash
# Rebuild the daax-agents devcontainer image
#
# This builds the container with AI coding tools (Claude, etc.)
# used by daax-cli and daax-web for AI coding sessions.
#
# Usage:
#   ./rebuild.sh
#
set -e

cd "$(dirname "$0")"

IMAGE_NAME="jpoley/daax-agents"
TAG="${1:-latest}"

echo "🔨 Building daax-agents devcontainer..."
docker build -t "$IMAGE_NAME:$TAG" devcontainer

echo "✅ Built $IMAGE_NAME:$TAG"
echo ""
echo "To push: docker push $IMAGE_NAME:$TAG"
