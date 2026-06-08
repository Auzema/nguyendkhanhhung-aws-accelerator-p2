#!/bin/bash
# 1-click deploy. Don gian: init + apply.
# Yeu cau bien moi truong TF_VAR_db_password (mat khau RDS).
# (Backend bucket + DynamoDB phai bootstrap truoc 1 lan - xem README Buoc 0.)
set -euo pipefail
cd "$(dirname "$0")"

# Cong cu can thiet
for c in terraform aws curl; do
  command -v "$c" >/dev/null || { echo "THIEU: $c"; exit 1; }
done

# AWS creds
aws sts get-caller-identity >/dev/null 2>&1 || { echo "Chay: aws configure"; exit 1; }

# Mat khau RDS
: "${TF_VAR_db_password:?Dat mat khau truoc: export TF_VAR_db_password='...' (>=8 ky tu)}"

# IP public (IPv4) -> mo SSH chi cho may nay
MYIP="$(curl -4 -s https://ifconfig.me)/32"
echo ">> IP cua ban: $MYIP"

terraform init -input=false
terraform apply -var="my_ip=$MYIP" -auto-approve

echo " XONG. Mo URL (cho ~1-2p cho nginx + RDS healthy):"
echo "   $(terraform output -raw web_url)"
