#!/bin/bash
# build-local.sh
# Build and test Docker image locally before pushing

set -euo pipefail

IMAGE_NAME="${1:-harness-cicd-app}"
TAG="${2:-local}"

echo "============================================"
echo "  Local Build & Test"
echo "============================================"

echo "[1/3] Building Docker image..."
docker build -t "$IMAGE_NAME:$TAG" ./app

echo ""
echo "[2/3] Running container for smoke test..."
CONTAINER_ID=$(docker run -d -p 3000:3000 "$IMAGE_NAME:$TAG")

# Wait for container to be ready
sleep 3

echo ""
echo "[3/3] Running smoke tests..."

# Test health endpoint
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health)
if [ "$HTTP_CODE" = "200" ]; then
  echo "  /health - PASS (HTTP $HTTP_CODE)"
else
  echo "  /health - FAIL (HTTP $HTTP_CODE)"
  docker logs "$CONTAINER_ID"
  docker stop "$CONTAINER_ID" && docker rm "$CONTAINER_ID"
  exit 1
fi

# Test root endpoint
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/)
if [ "$HTTP_CODE" = "200" ]; then
  echo "  /       - PASS (HTTP $HTTP_CODE)"
else
  echo "  /       - FAIL (HTTP $HTTP_CODE)"
fi

echo ""
echo "  Response from /health:"
curl -s http://localhost:3000/health | python3 -m json.tool

echo ""
echo "  Response from /:"
curl -s http://localhost:3000/ | python3 -m json.tool

# Cleanup
docker stop "$CONTAINER_ID" && docker rm "$CONTAINER_ID"

echo ""
echo "  Build and smoke tests PASSED!"
echo "  Image: $IMAGE_NAME:$TAG"
