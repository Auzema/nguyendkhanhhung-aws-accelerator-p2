#!/bin/bash
# 1-click deploy.
# Two-phase: kubernetes provider can ./kubeconfig ton tai luc plan, ma file do
# chi co sau khi cum minikube dung xong + scp ve. Nen apply -target truoc (dung cum
# + keo kubeconfig), roi apply day du (deploy app).
set -euo pipefail
cd "$(dirname "$0")"

# --- Kiem tra cong cu can thiet ---
for c in terraform aws curl ssh scp; do
  command -v "$c" >/dev/null || { echo "THIEU: $c. Cai truoc khi chay."; exit 1; }
done

# --- Kiem tra AWS creds ---
aws sts get-caller-identity >/dev/null 2>&1 || {
  echo "AWS creds chua cau hinh. Chay: aws configure"; exit 1; }

# --- IP public (IPv4) de mo SSH + apiserver chi cho may nay ---
MYIP="$(curl -4 -s https://ifconfig.me)/32"
case "$MYIP" in
  *:*|/32) echo "Khong lay duoc IPv4 (got: $MYIP). Kiem tra mang."; exit 1;;
esac
echo ">> IP cua ban: $MYIP"

echo "== Phase 1: ha tang (VPC/EC2/ALB) + minikube + keo kubeconfig =="
terraform init -input=false
terraform apply -target=null_resource.kubeconfig -var="my_ip=$MYIP" -auto-approve

echo "== Phase 2: deploy app (ConfigMap+Deployment+Service) qua kubernetes provider =="
terraform apply -var="my_ip=$MYIP" -auto-approve

URL="$(terraform output -raw alb_url)"
echo ""
echo "=================================================="
echo " XONG. Mo URL (cho ~60s cho ALB target healthy):"
echo "   $URL"
echo "=================================================="
