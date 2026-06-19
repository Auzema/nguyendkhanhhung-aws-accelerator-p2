# Media Store — W9 GitOps demo app

A tiny web app: upload images / gifs / videos, store them in **AWS S3**, and
play them back in the browser. Single Go binary serves both the UI and the API.
Deployed to the `w9` minikube cluster **via ArgoCD app-of-apps** (drop a file
into `argocd/apps/`, push, ArgoCD creates it — no `kubectl apply`).

## Architecture

```
Browser ──> media Pod (Go :8080)
              ├─ GET  /            UI (embedded static/index.html)
              ├─ POST /api/upload  -> PutObject to S3
              ├─ GET  /api/list    -> ListObjects + presigned GET URLs (1h)
              └─ DELETE /api/item  -> DeleteObject
                    │ AWS SDK, creds from k8s Secret `media-aws`
                    ▼
                 S3 bucket
```
No database: the S3 bucket listing *is* the gallery. No login.
Browser loads media directly from S3 via presigned URLs.

## ⚠️ Security — read first

AWS access keys are needed for S3. **Never commit them to Git** (this repo is
public; bots scan GitHub and abuse leaked keys within minutes).

The keys live in a Kubernetes Secret created **manually** with `kubectl`. The
manifests in Git only *reference* the Secret by name (`media-aws`) — they never
contain the keys. Use an IAM user scoped to **only this one bucket**
(least privilege) so a leak has minimal blast radius.

---

## Part 1 — AWS setup (you run these)

1. **Create an S3 bucket** (pick a globally-unique name; update it everywhere):
   ```bash
   aws s3 mb s3://gitapp-demo-hung --region us-east-1
   ```

2. **Create an IAM user with access to only that bucket.** Save this policy as
   `media-policy.json` (replace the bucket name):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"],
         "Resource": [
           "arn:aws:s3:::gitapp-demo-hung",
           "arn:aws:s3:::gitapp-demo-hung/*"
         ]
       }
     ]
   }
   ```
   ```bash
   aws iam create-user --user-name media-app
   aws iam put-user-policy --user-name media-app \
     --policy-name media-s3 --policy-document file://media-policy.json
   aws iam create-access-key --user-name media-app
   ```
   The last command prints `AccessKeyId` + `SecretAccessKey`. Copy them.

---

## Part 2 — Build & push the image (you run these)

The image name MUST match your Docker Hub username. If it is not `auzema`,
edit `gitops/k8s-media/deployment.yaml` (the `image:` line) too.

```bash
cd intern/cloud/w9/app-for-gitops
docker login                                  # log in to Docker Hub once
docker build -t auzema/media:v1 .
docker push auzema/media:v1
```
(Go is compiled *inside* the Docker build — you do not need Go installed.)

---

## Part 3 — Create the Secret + namespace (you run these — NOT in Git)

```bash
kubectl create namespace media
kubectl -n media create secret generic media-aws \
  --from-literal=AWS_ACCESS_KEY_ID=<your-access-key-id> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<your-secret-access-key>
```
Also confirm the bucket name + region in `deployment.yaml` match Part 1.

---

## Part 4 — Deploy via app-of-apps (the GitOps part)

```bash
# from the repo root
git add intern/cloud/w9/gitops/k8s-media intern/cloud/w9/gitops/argocd/apps/media.yaml
git commit -m "add media app"
git push origin main
```
That is it — **no `kubectl apply`**. The `root` Application watches
`argocd/apps/`, sees the new `media.yaml`, and creates the `media` Application,
which deploys the pod + service. Force a refresh to skip the ~3-min poll:
```bash
kubectl -n argocd annotate app root argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd get applications        # root + web + media, all Synced/Healthy
```

## Part 5 — Open it

```bash
kubectl -n media port-forward svc/media 9090:80
# browse http://localhost:9090  -> upload an image/gif/video, watch it play
```

## Local dev (optional, needs AWS creds in your shell)

```bash
export S3_BUCKET=gitapp-demo-hung AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...
go run .        # if you install Go; otherwise just use Docker
```

## Files

| Path | What |
|------|------|
| `app-for-gitops/main.go` | Go server: UI + upload/list/delete API |
| `app-for-gitops/static/index.html` | UI (upload form + gallery) |
| `app-for-gitops/Dockerfile` | multi-stage build (no local Go needed) |
| `gitops/k8s-media/deployment.yaml` | media Deployment (image + env + Secret ref) |
| `gitops/k8s-media/service.yaml` | media Service (:80 -> :8080) |
| `gitops/argocd/apps/media.yaml` | ArgoCD Application (root auto-creates it) |
