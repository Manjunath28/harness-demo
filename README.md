# Harness CI/CD + STO Pipeline

End-to-end CI/CD pipeline with integrated Security Testing Orchestration (STO) using Harness Free Tier and a local Kubernetes cluster.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    Harness Pipeline                                │
├─────────────────┬──────────────────┬─────────────────────────────┤
│   CI Stage      │   STO Stage      │   CD Stage                   │
│                 │                  │                               │
│ • Clone repo    │ • Trivy scan     │ • Rolling deploy to K8s      │
│ • Run tests     │ • Semgrep SAST   │ • Health check validation    │
│ • Build image   │ • Security gate  │ • Auto-rollback on failure   │
│ • Push to DHR   │   (fail on CRIT) │                               │
└─────────────────┴──────────────────┴─────────────────────────────┘
         │                  │                      │
         ▼                  ▼                      ▼
   ┌──────────┐     ┌─────────────┐      ┌──────────────────┐
   │Docker Hub│     │ Fail if     │      │ Local K8s        │
   │ Registry │     │ CRITICAL    │      │ (minikube/kind)  │
   └──────────┘     │ vulns found │      └──────────────────┘
                    └─────────────┘
```

## Project Structure

```
.
├── .harness/
│   ├── pipeline.yaml       # Main Harness pipeline definition
│   ├── service.yaml        # Harness service definition
│   ├── environment.yaml    # Environment configuration
│   ├── infrastructure.yaml # K8s infrastructure definition
│   └── inputset.yaml       # Default input set
├── app/
│   ├── server.js           # Node.js Express application
│   ├── server.test.js      # Jest unit tests
│   ├── package.json        # Dependencies
│   ├── Dockerfile          # Multi-stage Docker build
│   └── .dockerignore
├── k8s/
│   ├── namespace.yaml      # Kubernetes namespace
│   ├── deployment.yaml     # Deployment with rolling strategy
│   └── service.yaml        # NodePort service
├── scripts/
│   ├── setup-local-cluster.sh    # Minikube setup
│   ├── build-local.sh            # Local build & test
│   ├── validate-deployment.sh    # Post-deploy validation
│   └── cleanup.sh                # Teardown resources
└── README.md
```

## Prerequisites

- **Docker** (v20+)
- **minikube** or **kind** (local Kubernetes)
- **kubectl** (v1.28+)
- **Harness Free Tier account** ([sign up](https://app.harness.io/auth/#/signup))
- **Docker Hub account** (for image registry)
- **GitHub account** (source code hosting)

## Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/<your-username>/harness-cicd-sto.git
cd harness-cicd-sto
```

### 2. Set Up Local Kubernetes Cluster

```bash
./scripts/setup-local-cluster.sh
```

This script will:
- Validate prerequisites (docker, minikube, kubectl)
- Start a minikube cluster with 2 CPUs and 4GB RAM
- Enable ingress and metrics-server addons
- Create required namespaces (`harness-demo`, `harness-build`)

### 3. Local Build & Smoke Test

```bash
./scripts/build-local.sh
```

### 4. Configure Harness

#### a) Install Harness Delegate

1. Navigate to **Project Settings > Delegates** in Harness UI
2. Click **New Delegate > Kubernetes**
3. Apply the downloaded YAML to your cluster:
   ```bash
   kubectl apply -f harness-delegate.yaml
   ```
4. Verify: `kubectl get pods -n harness-delegate-ng`

#### b) Create Connectors

| Connector | Type | Purpose |
|-----------|------|---------|
| `github_connector` | GitHub | Source code access |
| `dockerhub_connector` | Docker Registry | Push/pull images |
| `k8s_connector` | Kubernetes | Deploy to cluster |

**Important:** Use Harness Secrets Manager for all credentials. Never hardcode tokens.

#### c) Import Pipeline

1. Go to **Pipelines > Create Pipeline**
2. Choose **Import from Git**
3. Point to `.harness/pipeline.yaml` in your repo

### 5. Run the Pipeline

1. Click **Run** on the pipeline
2. Provide inputs:
   - **Branch**: `main`
   - **docker_repo**: `<your-dockerhub-username>/harness-cicd-app`
3. Monitor execution across all 3 stages

### 6. Validate Deployment

```bash
./scripts/validate-deployment.sh
```

Or access directly:
```bash
kubectl port-forward svc/harness-cicd-app 8080:80 -n harness-demo
curl http://localhost:8080/health
```

## Pipeline Stages Explained

### Stage 1: CI (Build & Push)

- **Clone**: Fetches source from GitHub
- **Test**: Runs Jest unit tests with coverage reporting
- **Build**: Multi-stage Docker build (minimal Alpine image, non-root user)
- **Push**: Tags with commit SHA + `latest`, pushes to Docker Hub

### Stage 2: STO (Security Testing)

#### Container Scan (Aqua Trivy)
- Scans the built Docker image for OS and library vulnerabilities
- Checks against CVE databases

#### SAST Scan (Semgrep) - Bonus
- Static analysis of source code
- Detects common security patterns (injection, hardcoded secrets, etc.)

### Security Gate

The pipeline is configured to **automatically fail** if any **CRITICAL** severity vulnerabilities are detected:

```yaml
advanced:
  fail_on_severity: critical
```

This enforces a shift-left security posture:
- **CRITICAL** → Pipeline fails (blocks deployment)
- **HIGH/MEDIUM/LOW** → Pipeline continues (logged for review)

If the STO stage fails, the CD stage is never reached, preventing insecure code from being deployed.

### Stage 3: CD (Deploy to Kubernetes)

- **Rolling Deployment**: Zero-downtime updates with `maxSurge: 1, maxUnavailable: 0`
- **Health Verification**: Automated /health endpoint check with retries
- **Auto-Rollback**: If deployment fails, automatically rolls back to previous version

## Deployment Strategy

**Rolling Update** was chosen because:
- Zero-downtime deployments
- Gradual rollout with health checks
- Automatic rollback capability
- Simple to configure and understand

Configuration:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # At most 1 extra pod during update
    maxUnavailable: 0  # Never reduce available pods below desired
```

## Security Design Decisions

| Decision | Rationale |
|----------|-----------|
| Multi-stage Docker build | Smaller attack surface, no build tools in production |
| Non-root container user | Principle of least privilege |
| Alpine base image | Minimal OS packages = fewer vulnerabilities |
| `fail_on_severity: critical` | Block deployment of critically vulnerable code |
| Harness Secrets Manager | No credentials in code or environment |
| Resource limits | Prevent DoS from runaway containers |
| Health checks (liveness + readiness) | Automatic recovery from failures |

## Bonus Features Implemented

### Shift-Left Security
- Pipeline can be triggered on PRs via Harness triggers
- Security scans run before merge, preventing vulnerable code from entering main

### Failure Handling
- **Rollback**: Automatic `K8sRollingRollback` on deployment failure
- **Retry Logic**: Health validation retries with backoff (5 attempts, 10s interval)
- **Stage Abort**: STO failure aborts pipeline before CD stage executes

### Secrets Management
- All credentials stored in Harness Secrets Manager
- Connectors reference secrets by ID, never by value
- No hardcoded tokens in pipeline YAML or application code

## Assumptions & Trade-offs

| Assumption | Trade-off |
|------------|-----------|
| Using minikube for local K8s | Limited resources; fine for demo, not production |
| Docker Hub as registry | Free tier has rate limits; alternatives: GHCR, ECR |
| NodePort for access | Not production-grade; real clusters use Ingress/LB |
| Single environment (dev) | Simplified; production would have dev → staging → prod |
| Trivy for container scan | Free and well-supported; alternatives: Snyk, Grype |
| 2 replicas | Demonstrates HA basics; production needs capacity planning |

## Troubleshooting

### Pipeline fails at Build step
- Verify Docker Hub credentials in Harness connector
- Check delegate has Docker socket access

### STO scan fails with timeout
- Ensure delegate has internet access for CVE database downloads
- Increase step timeout if on slow network

### Deployment not accessible
```bash
# Check pods are running
kubectl get pods -n harness-demo

# Check pod logs
kubectl logs -l app=harness-cicd-app -n harness-demo

# Check service endpoints
kubectl get endpoints harness-cicd-app -n harness-demo
```

### Delegate not connecting
```bash
kubectl get pods -n harness-delegate-ng
kubectl logs -l app=harness-delegate -n harness-delegate-ng
```

## Cleanup

```bash
./scripts/cleanup.sh
```

## License

MIT
