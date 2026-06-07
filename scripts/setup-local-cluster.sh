#!/bin/bash
# setup-local-cluster.sh
# Sets up a local Kubernetes cluster using minikube for the Harness CI/CD + STO demo

set -euo pipefail

CLUSTER_NAME="harness-demo"
K8S_VERSION="v1.28.0"

echo "============================================"
echo "  Harness CI/CD + STO - Local Cluster Setup"
echo "============================================"

# Check prerequisites
check_prerequisites() {
  echo "[1/5] Checking prerequisites..."

  local missing=()

  if ! command -v docker &> /dev/null; then
    missing+=("docker")
  fi

  if ! command -v minikube &> /dev/null; then
    missing+=("minikube")
  fi

  if ! command -v kubectl &> /dev/null; then
    missing+=("kubectl")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo "ERROR: Missing required tools: ${missing[*]}"
    echo "Install them before running this script."
    exit 1
  fi

  echo "  All prerequisites met."
}

# Start minikube cluster
start_cluster() {
  echo "[2/5] Starting minikube cluster..."

  if minikube status --profile "$CLUSTER_NAME" &> /dev/null; then
    echo "  Cluster '$CLUSTER_NAME' already exists. Reusing it."
  else
    minikube start \
      --profile "$CLUSTER_NAME" \
      --kubernetes-version="$K8S_VERSION" \
      --cpus=2 \
      --memory=4096 \
      --driver=docker \
      --addons=ingress,metrics-server
  fi

  kubectl config use-context "$CLUSTER_NAME"
  echo "  Cluster is running."
}

# Create namespaces
create_namespaces() {
  echo "[3/5] Creating namespaces..."

  kubectl apply -f k8s/namespace.yaml

  # Build namespace for Harness CI/CD runners
  kubectl create namespace harness-build --dry-run=client -o yaml | kubectl apply -f -

  echo "  Namespaces created."
}

# Install Harness Delegate
install_delegate() {
  echo "[4/5] Installing Harness Delegate..."
  echo "  NOTE: You need to install the Harness Delegate manually."
  echo "  Steps:"
  echo "    1. Go to Harness UI > Project Settings > Delegates"
  echo "    2. Click 'New Delegate' > Kubernetes"
  echo "    3. Download and apply the YAML manifest"
  echo "    4. Verify: kubectl get pods -n harness-delegate-ng"
  echo ""
}

# Verify setup
verify_setup() {
  echo "[5/5] Verifying cluster setup..."

  echo "  Nodes:"
  kubectl get nodes

  echo ""
  echo "  Namespaces:"
  kubectl get namespaces

  echo ""
  echo "  Cluster info:"
  kubectl cluster-info

  echo ""
  echo "============================================"
  echo "  Setup Complete!"
  echo "============================================"
  echo ""
  echo "Next steps:"
  echo "  1. Install Harness Delegate (see step 4 above)"
  echo "  2. Configure connectors in Harness UI"
  echo "  3. Run the pipeline!"
  echo ""
  echo "Access app after deployment:"
  echo "  minikube service harness-cicd-app -n harness-demo --profile $CLUSTER_NAME"
  echo "  OR"
  echo "  kubectl port-forward svc/harness-cicd-app 8080:80 -n harness-demo"
}

# Main
check_prerequisites
start_cluster
create_namespaces
install_delegate
verify_setup
