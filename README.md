# Harness CI/CD + STO Pipeline

End-to-end CI/CD pipeline with integrated Security Testing Orchestration (STO) using Harness Free Tier, deployed to a local Kubernetes cluster (Rancher Desktop).

**Author:** Manjunath Y  
**Harness Account:** manjunath.chavan2017  
**GitHub Repo:** [Manjunath28/harness-demo](https://github.com/Manjunath28/harness-demo)

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Harness Pipeline                                     │
├───────────────────┬───────────────────┬───────────────────┬─────────────────┤
│   CI Stage        │   CD Stage        │  Post-Deploy      │                 │
│   (build)         │   (deploy-k8s)    │  Stage            │                 │
│                   │                   │                   │                 │
│ • Clone repo      │ • K8s Rolling     │ • Health Check    │                 │
│ • npm install     │   Deploy          │   (HTTP /health)  │                 │
│ • npm test        │ • Auto-rollback   │ • Image Promotion │                 │
│ • Docker build    │   on failure      │   (:latest→:stable)│                │
│ • Push :seq,:latest│                  │ • GitOps PR       │                 │
│ • Trivy scan      │                   │                   │                 │
│ • SAST scan       │                   │                   │                 │
│   (security gate) │                   │                   │                 │
└───────────────────┴───────────────────┴───────────────────┴─────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
   ┌──────────┐      ┌──────────────┐     ┌──────────────────┐
   │Docker Hub│      │ Rancher      │     │ GitHub PR        │
   │ Registry │      │ Desktop K8s  │     │ (manifest update)│
   └──────────┘      └──────────────┘     └──────────────────┘
```

## Project Structure

```
.
├── .harness/
│   ├── pipelines/              # Harness pipeline YAML (synced from Harness)
│   ├── service.yaml            # Harness service definition
│   ├── environment.yaml        # Environment configuration
│   └── infrastructure.yaml     # K8s infrastructure definition
├── app/
│   ├── server.js               # Node.js Express application
│   ├── server.test.js          # Jest unit tests
│   ├── package.json            # Dependencies
│   └── Dockerfile              # Multi-stage Docker build
├── infra/
│   ├── harness-delegate.yaml   # Delegate deployment (one-time setup)
│   └── namespace.yaml          # K8s namespace definition
├── k8s/
│   ├── deployment.yaml         # Deployment with rolling strategy
│   └── service.yaml            # NodePort service (port 30080)
└── README.md
```

## Prerequisites

- **Rancher Desktop** (local Kubernetes cluster)
- **kubectl** (v1.28+)
- **Harness Free Tier account** ([sign up](https://app.harness.io/auth/#/signup))
- **Docker Hub account** (image registry)
- **GitHub account** (source code hosting)

## Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/Manjunath28/harness-demo.git
cd harness-demo
```

### 2. Set Up Local Kubernetes Cluster

Install and start **Rancher Desktop** (uses k3s under the hood):
```bash
# Verify cluster is running
kubectl get nodes
# Expected: lima-rancher-desktop   Ready
```

Create the application namespace:
```bash
kubectl apply -f infra/namespace.yaml
```

### 3. Install Harness Delegate

```bash
kubectl apply -f infra/harness-delegate.yaml
kubectl get pods -n harness-delegate-ng
# Expected: kubernetes-delegate-xxx   Running
```

### 4. Configure Harness Connectors

| Connector | Type | Purpose |
|-----------|------|---------|
| `account.Github` | GitHub | Source code access |
| `Manjunathpersonal` | Docker Registry | Push/pull images |
| `rancher-desktop` | Kubernetes (via delegate) | Deploy to cluster |

### 5. Run the Pipeline

1. Go to **Pipelines** → **Build harness-demo**
2. Click **Run** → Branch: `main`
3. Monitor all stages: build → deploy-k8s → post-deploy-stage

### 6. Validate Deployment

```bash
curl http://localhost:30080/health
# {"status":"healthy","timestamp":"...","uptime":...}

curl http://localhost:30080/
# {"message":"Hello World","service":"harness-cicd-sto-app","version":"latest"}
```

## Pipeline Stages Explained

### Stage 1: CI (build)

| Step | Description |
|------|-------------|
| Clone | Fetches source from GitHub (`Manjunath28/harness-demo`) |
| Install | `npm ci` — installs dependencies |
| Test | `npm test` — runs Jest unit tests |
| Build & Push | Multi-stage Docker build → pushes `pes2ug19cs219/harness-test:<sequenceId>` + `:latest` |
| Container Scan (Trivy) | Scans image for OS/library vulnerabilities, **fails on CRITICAL** |
| SAST Scan (Semgrep) | Static code analysis for security issues |

### Stage 2: CD (deploy-k8s)

| Step | Description |
|------|-------------|
| K8s Rolling Deploy | Deploys `pes2ug19cs219/harness-test:latest` with zero-downtime rolling strategy |
| Auto-Rollback | On failure, `K8sRollingRollback` restores previous version |

### Stage 3: Post-Deploy (post-deploy-stage)

| Step | Description |
|------|-------------|
| Health Check (HTTP) | GET `/health` endpoint, asserts HTTP 200 |
| Image Promotion | Tags verified image as `:stable` using regctl |
| GitOps PR | Creates a GitHub PR to update `k8s/deployment.yaml` with promoted tag |

## How Security Gating Works

The pipeline enforces a **shift-left security** approach:

```
Code Push → Build → Security Scan → Deploy (only if scan passes)
```

### Container Scan (Trivy)
```bash
trivy image --exit-code 1 --severity CRITICAL --no-progress pes2ug19cs219/harness-test:<tag>
```
- `--exit-code 1`: Fails the step if vulnerabilities are found
- `--severity CRITICAL`: Only blocks on critical CVEs
- If this step fails → **pipeline stops**, CD stage never executes

### SAST Scan (Semgrep)
```bash
semgrep scan --config auto --error --severity ERROR app/
```
- Analyzes source code for injection, hardcoded secrets, insecure patterns
- `--error`: Fails on high-severity findings

### Security Gate Matrix

| Severity | Action |
|----------|--------|
| CRITICAL | Pipeline **FAILS** — deployment blocked |
| HIGH/MEDIUM/LOW | Pipeline continues — logged for review |

### Image Promotion as Security Signal
Only images that pass ALL checks get promoted to `:stable`:
```
:latest (unverified) → Security Scan ✓ → Deploy ✓ → Health Check ✓ → :stable (verified)
```

## Deployment Strategy

**Rolling Update** configuration:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # At most 1 extra pod during update
    maxUnavailable: 0  # Never reduce available pods below desired
```

Why Rolling Update:
- Zero-downtime deployments
- Gradual rollout with health checks
- Automatic rollback on failure
- 2 replicas ensure availability during updates

## Artifact Promotion & GitOps

After successful deployment and health verification:
1. Image is re-tagged from `:latest` → `:stable` at registry level
2. A GitHub PR is automatically created to update `k8s/deployment.yaml`
3. This provides an audit trail of what was deployed and when

## Assumptions & Trade-offs

| Assumption | Rationale |
|------------|-----------|
| Rancher Desktop for local K8s | Free, lightweight k3s cluster for development |
| Docker Hub as registry | Free tier; production would use private registry |
| NodePort (30080) for access | Simple for local dev; production uses Ingress/LB |
| Single environment (dev) | Simplified demo; production: dev → staging → prod |
| Trivy for container scan | Free, well-maintained, fast CVE scanning |
| Semgrep for SAST | Free, supports JS/Node.js, extensive rule library |
| 2 replicas | Demonstrates HA; production needs capacity planning |
| Harness Cloud for CI | Free tier build infrastructure, no self-hosted runners |
| Delegate for CD | Required for local K8s access from Harness SaaS |

## Secrets Management

| Secret | Purpose | Stored In |
|--------|---------|-----------|
| `docker-secret` | Docker Hub credentials for push | Harness Secrets Manager |
| `github_pat` | GitHub PAT for GitOps PR creation | Harness Secrets Manager |

All credentials are stored in Harness Secrets Manager — never hardcoded in pipeline YAML or source code.

## Troubleshooting

### Pipeline fails at Docker Build
- Verify Docker Hub connector credentials
- Ensure `app/Dockerfile` path is correct in the step config

### Security scan fails (expected)
- CRITICAL vulnerabilities found → fix the base image or dependencies
- This is **working as designed** — the security gate is protecting production

### CD stage fails with ImagePullBackOff
- Ensure CI pushed the `:latest` tag (check Docker Hub)
- Verify the K8s nodes can reach Docker Hub

### Health check fails in post-deploy
- Check pods are running: `kubectl get pods -n harness-demo`
- Verify service: `kubectl get svc -n harness-demo`
- Test locally: `curl http://localhost:30080/health`

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Application | Node.js + Express |
| Testing | Jest |
| Container | Docker (multi-stage, Alpine, non-root) |
| CI/CD Platform | Harness Free Tier |
| Orchestration | Kubernetes (k3s via Rancher Desktop) |
| Container Scan | Aqua Trivy |
| SAST | Semgrep |
| Registry | Docker Hub |
| Source Control | GitHub |

## License

MIT
