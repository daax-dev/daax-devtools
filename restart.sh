#!/bin/bash
# Rebuild and restart Daax container

set -e

CONTAINER_NAME="daax"
NETWORK_NAME="daax-net"
IMAGE_NAME="daax"

# Workspace path - use DAAX_WORKSPACE env var or default to ~/prj
WORKSPACE_PATH="${DAAX_WORKSPACE:-$HOME/prj}"

echo "🛑 Stopping existing container..."
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "🔌 Freeing ports 4200/4201..."
if command -v lsof >/dev/null 2>&1; then
  lsof -ti:4200,4201 | xargs kill -9 2>/dev/null || true
else
  echo "   lsof not found, skipping port cleanup (only available on Unix systems)"
fi


echo "🌐 Ensuring network exists..."
docker network create "$NETWORK_NAME" 2>/dev/null || true

echo "🚀 Starting container..."
echo "   Workspace: $WORKSPACE_PATH"
docker run -d \
  --name "$CONTAINER_NAME" \
  --network "$NETWORK_NAME" \
  -p 4200:4200 \
  -p 4201:4201 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$WORKSPACE_PATH:/workspace" \
  -e DOCKER_NETWORK="$NETWORK_NAME" \
  -e HOST_WORKSPACE_PATH="$WORKSPACE_PATH" \
  -e NEXT_PUBLIC_DEPLOYMENT_MODE="container" \
  "$IMAGE_NAME"

echo "✅ Daax is running at http://localhost:4200"
echo "📋 View logs: docker logs -f $CONTAINER_NAME"
echo ""
echo "💡 To use a different workspace, set DAAX_WORKSPACE before running:"
echo "   DAAX_WORKSPACE=~/projects ./rebuild.sh"
