#!/bin/bash
# Xoa sach ha tang (tranh ton tien): EC2, EIP, RDS, S3, VPC...
# Backend (bucket tfstate + DynamoDB lock) KHONG bi xoa - xoa tay neu can.
set -euo pipefail
cd "$(dirname "$0")"

: "${TF_VAR_db_password:?export TF_VAR_db_password='...' truoc khi destroy}"

MYIP="$(curl -4 -s https://ifconfig.me)/32"
terraform destroy -var="my_ip=$MYIP" -auto-approve
echo ">> Da destroy"
