#!/bin/bash
# validate-deployment.sh
# Post-deployment validation script to verify application health

set -euo pipefail

NAMESPACE="${1:-harness-demo}"
SERVICE_NAME="${2:-harness-cicd-app}"
MAX_RETRIES=10
RETRY_INTERVAL=5

echo "============================================"
echo "  Post-Deployment Validation"
echo "============================================"
echo "  Namespace: $NAMESPACE"
echo "  Service:   $SERVICE_NAME"
echo ""

# Check pod status
check_pods() {
  echo "[1/4] Checking pod status..."

  local ready_pods
  ready_pods=$(kubectl get pods -n "$NAMESPACE" -l app="$SERVICE_NAME" \
    --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')

  if [ "$ready_pods" -eq 0 ]; then
    echo "  ERROR: No running pods found!"
    kubectl get pods -n "$NAMESPACE" -l app="$SERVICE_NAME"
    return 1
  fi

  echo "  $ready_pods pod(s) running."
  kubectl get pods -n "$NAMESPACE" -l app="$SERVICE_NAME" -o wide
}

# Check service
check_service() {
  echo ""
  echo "[2/4] Checking service..."

  if kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "  Service exists."
    kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE"
  else
    echo "  ERROR: Service '$SERVICE_NAME' not found!"
    return 1
  fi
}

# Port-forward and test health endpoint
test_health_endpoint() {
  echo ""
  echo "[3/4] Testing /health endpoint..."

  # Start port-forward in background
  kubectl port-forward "svc/$SERVICE_NAME" 8080:80 -n "$NAMESPACE" &
  local pf_pid=$!

  # Give port-forward time to establish
  sleep 3

  local retry_count=0
  local success=false

  while [ $retry_count -lt $MAX_RETRIES ]; do
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
      echo "  Health check PASSED (HTTP $http_code)"
      success=true
      break
    fi

    retry_count=$((retry_count + 1))
    echo "  Attempt $retry_count/$MAX_RETRIES: HTTP $http_code. Retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
  done

  if [ "$success" = "true" ]; then
    echo ""
    echo "  Response body:"
    curl -s http://localhost:8080/health | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8080/health
  else
    echo "  ERROR: Health check FAILED after $MAX_RETRIES attempts!"
    kill $pf_pid 2>/dev/null || true
    return 1
  fi

  # Test root endpoint too
  echo ""
  echo "  Testing / endpoint:"
  curl -s http://localhost:8080/ | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8080/

  # Cleanup port-forward
  kill $pf_pid 2>/dev/null || true
}

# Summary
summary() {
  echo ""
  echo "[4/4] Deployment Summary"
  echo "============================================"
  echo "  Status: ALL CHECKS PASSED"
  echo "  App is accessible via:"
  echo "    - kubectl port-forward svc/$SERVICE_NAME 8080:80 -n $NAMESPACE"
  echo "    - NodePort: $(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo 'N/A')"
  echo "============================================"
}

# Main
check_pods
check_service
test_health_endpoint
summary
