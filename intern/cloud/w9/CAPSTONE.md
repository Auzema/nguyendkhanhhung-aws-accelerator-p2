# W9 Capstone — "Ship Smartly"

One project tying together everything: **Terraform → Kubernetes → GitOps →
Observability → Canary**. The goal is a full, demoable pipeline: change a
version through Git, let a canary roll it out, let metrics judge it, and
auto-rollback a bad release — with monitoring + alerting proving it.

## Architecture

```
Terraform ──creates──> AWS: S3 bucket + scoped IAM user (Infra as Code)
                              │ access key
minikube w9 (--cpus=4 --memory=6g)
   └─ ArgoCD (app-of-apps: one root → many apps)
        ├─ web                    nginx (hello GitOps)
        ├─ media                  Go + S3 (uses the TF-created bucket)
        ├─ api                    Flask /metrics, deployed as an Argo Rollout (canary)
        ├─ kube-prometheus-stack  Prometheus + Grafana + Alertmanager
        └─ argo-rollouts          canary controller
   Observability: SLO (PrometheusRule) + burn-rate alert → email
   Canary: AnalysisTemplate queries Prometheus success-rate → auto-abort
```

Everything except secrets lives in Git. ArgoCD reconciles the cluster to Git.

## Repo layout

```
intern/cloud/w9/
├── terraform/         S3 + IAM as code (replaces manual aws CLI)
├── app-for-gitops/    media app (Go + S3)
├── api-app/           api app (Flask + /metrics + ERROR_RATE)
└── gitops/
    ├── k8s/           web Deployment
    ├── k8s-media/     media Deployment + Service
    ├── k8s-api/       Rollout + Service + ServiceMonitor + AnalysisTemplate
    └── argocd/
        ├── root.yaml  app-of-apps root (watches apps/)
        └── apps/      web, media, api, kube-prometheus-stack, argo-rollouts
```

## Phases (each is one hands-on session)

| Phase | What | Demo to capture |
|-------|------|-----------------|
| 1 | **Terraform**: `apply` → S3 bucket + IAM user/key | `terraform apply` output, bucket in console |
| 2 | **Cluster + GitOps**: recreate w9 (6g), install ArgoCD, apply root, recreate media Secret | ArgoCD UI: web+media Synced/Healthy |
| 3 | **Observability**: add kube-prometheus-stack + argo-rollouts Applications | Grafana opens, Prometheus Targets UP |
| 4 | **api app**: Flask /metrics, build + `minikube image load`, k8s-api Rollout/Service/ServiceMonitor | Prometheus query `flask_http_request_total` rising |
| 5 | **Canary (manual)**: bump VERSION via Git → promote/abort by hand | rollouts dashboard: 25% pause → promote → 100% |
| 6 | **Challenge**: AnalysisTemplate auto-abort + SLO + alert→email | clip: bad version auto-aborts + rollback; alert email |

## Security rules (this repo is PUBLIC)

- **Never commit** AWS keys. They are produced by Terraform and put into a
  Kubernetes Secret manually (`kubectl`), never into Git.
- **Never commit** `*.tfstate` — it contains the secret access key in plaintext.
  See `terraform/.gitignore`.
- IAM user is scoped to the one bucket (least privilege).

## Definition of done (Challenge "ĐẠT" — all four)

1. All changes via Git; ArgoCD Synced (no drift); reproducible from Git.
2. `git revert` rollback < 5 minutes.
3. One SLO + one alert that fires to a personal email when errors are injected.
4. Canary auto-aborts a bad version and rolls back (the most important one).
