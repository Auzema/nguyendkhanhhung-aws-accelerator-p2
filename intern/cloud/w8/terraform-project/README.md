# K8s on AWS — Terraform 1-Click

Dựng **1 EC2**, chạy **minikube** (Kubernetes self-managed) bên trong, deploy **app static HTML**, expose ra **Internet qua ALB** — tất cả bằng **một lệnh** (`./deploy.sh`, gói 2 phase `terraform apply`).

## Kiến trúc

```
                    Internet
                       │  :80 (HTTP)
                       ▼
                 ┌───────────┐
                 │    ALB    │  internet-facing, 2 public subnet / 2 AZ
                 └───────────┘
                       │  target: EC2:30080
                       ▼
   ┌───────────────────────────────────────────────┐
   │ EC2 (t4g.medium, Amazon Linux 2023 arm64)       │
   │  Elastic IP (co dinh)                           │
   │                                                 │
   │  socat :30080 ──▶ minikube NodePort :30080      │
   │  socat :8443  ──▶ minikube apiserver            │
   │                                                 │
   │  ┌─────────── minikube (docker driver) ───────┐ │
   │  │ Deployment web (nginx x2)                  │ │
   │  │   mount ConfigMap: index.html + yes_web.mp4│ │
   │  │ Service web (NodePort 30080)               │ │
   │  └────────────────────────────────────────────┘ │
   └───────────────────────────────────────────────┘
                       ▲
                       │ kubernetes provider (https://EIP:8443)
              ┌─────────────────────┐
              │ Terraform (may ban) │  aws + tls + local + null + kubernetes
              └─────────────────────┘
```

## 5 Terraform provider (mỗi cái 1 việc thật)

| Provider | Vai trò |
|----------|---------|
| `aws` | Dựng toàn bộ hạ tầng: VPC, subnet, IGW, EC2, EIP, ALB, target group, SG |
| `tls` | Sinh cặp khoá SSH (RSA 4096) |
| `local` | Ghi private key ra `*.pem` (quyền 0400) |
| `null` | `null_resource`: SSH chờ cụm sẵn sàng + scp kubeconfig về máy |
| `kubernetes` | Deploy app vào cụm: ConfigMap + Deployment + Service |

## Yêu cầu (máy chạy Terraform)

- `terraform` ≥ 1.5, `aws` CLI (đã `aws configure` với IAM user — **không dùng root**)
- `curl`, `ssh`, `scp`
- Quyền AWS: EC2 (gồm VPC) + ElasticLoadBalancing. `AdministratorAccess` là đủ.

## Chạy (1-click)

```bash
./deploy.sh
```

Script tự: lấy IP public của máy → `terraform init` → **2 phase apply** → in URL ALB.
Mở URL (chờ ~60s cho ALB health check) → thấy trang + video.

> Mặc định: region `us-east-1`, instance `t4g.medium`. Đổi qua `variables.tf` hoặc cờ `-var`. `my_ip` được `deploy.sh` tự lấy (`ifconfig.me`).

> **Vì sao 2 phase?** Provider `kubernetes` cần file `./kubeconfig` tồn tại **lúc plan**, nhưng kubeconfig chỉ có sau khi minikube dựng xong + scp về. Terraform không cho provider config phụ thuộc resource chưa tạo → pattern chuẩn: `apply -target=null_resource.kubeconfig` (dựng cụm + kéo kubeconfig) **rồi** `apply` (deploy app). `deploy.sh` gói cả hai.

## Dọn (tránh tốn tiền)

```bash
./destroy.sh
```

ALB tính tiền **theo giờ** kể cả không traffic → destroy sau khi xong.

## Cách hoạt động (chi tiết để bảo vệ thiết kế)

1. **EC2 + Elastic IP**: IP cố định. Nếu dùng auto-assign IP, mỗi lần stop/start/replace IP đổi → vỡ cert apiserver + kubeconfig. EIP được inject vào `user_data` qua `templatefile` để minikube sinh cert hợp lệ cho đúng IP đó (`--apiserver-ips`).
2. **minikube self-managed** (docker driver) chạy trong EC2 — không phải EKS (managed, tốn phí, không thoả "self-managed").
3. **ALB → app**: NodePort của minikube bind trên IP container (192.168.49.2), không ra host → `socat` forward `EC2:30080 → minikube:30080`. ALB target = `EC2:30080`. SG ép app chỉ nhận traffic **từ ALB** (SG-reference), không cho gõ thẳng.
4. **kubernetes provider → cụm**: apiserver trong EC2 → `socat` forward `EC2:8443 → minikube:8443`. kubeconfig (cert nhúng, server = `https://EIP:8443`) được scp về máy chạy Terraform.
5. **App = static HTML**: `index.html` + `yes_web.mp4` đặt trong **ConfigMap** (binaryData), mount vào nginx. Không build image riêng.

## Bảo mật

- SSH (22) + apiserver (8443): chỉ mở cho **IP máy chạy** (`var.my_ip`).
- App (30080) trên EC2: chỉ nhận từ **Security Group của ALB** (không phải `0.0.0.0/0`).
- Chỉ port **80 trên ALB** mở ra Internet.
- `*.pem`, `kubeconfig`, `*.tfstate*`, `.terraform/` nằm trong `.gitignore` — **không commit**.
- ⚠️ `*.tfstate` chứa **SSH private key** (do `tls_private_key` sinh) ở dạng plaintext → tuyệt đối không đẩy state lên git/remote public.

## File

| File | Nội dung |
|------|----------|
| `providers.tf` | 5 provider + cấu hình aws/kubernetes |
| `variables.tf` | region, instance_type, project, subnet_cidrs, my_ip |
| `network.tf` | VPC, 2 public subnet (2 AZ), IGW, route table |
| `compute.tf` | EIP, key pair (tls), AMI arm64, SG-EC2, EC2 instance |
| `alb.tf` | SG-ALB, ALB, target group, listener, attachment |
| `k8s.tf` | null_resource (kéo kubeconfig) + ConfigMap/Deployment/Service |
| `user_data.sh.tpl` | Script EC2 boot: docker, minikube, socat, kubeconfig |
| `outputs.tf` | alb_url, ec2_public_ip, ssh_command |
| `deploy.sh` / `destroy.sh` | 1-click lên / xuống |
| `.gitignore` | Chặn commit state + key: `*.tfstate*`, `*.pem`, `kubeconfig`, `.terraform/` |
