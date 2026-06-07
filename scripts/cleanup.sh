#!/bin/bash
# cleanup.sh
# Clean up all resources created by this demo

set -euo pipefail

CLUSTER_NAME="harness-demo"

echo "============================================"
echo "  Cleanup - Harness CI/CD + STO Demo"
echo "============================================"
echo ""

read -rp "This will delete the minikube cluster and all resources. Continue? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "[1/3] Deleting Kubernetes resources..."
kubectl delete namespace harness-demo --ignore-not-found
kubectl delete namespace harness-build --ignore-not-found

echo ""
echo "[2/3] Stopping minikube cluster..."
minikube stop --profile "$CLUSTER_NAME" 2>/dev/null || true
minikube delete --profile "$CLUSTER_NAME" 2>/dev/null || true

echo ""
echo "[3/3] Removing local Docker images..."
docker rmi harness-cicd-app:local 2>/dev/null || true

echo ""
echo "  Cleanup complete!"
