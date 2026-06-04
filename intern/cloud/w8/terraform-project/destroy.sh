#!/bin/bash
# Xoa sach toan bo ha tang (tranh ton tien). EIP, EC2, ALB, VPC... bi xoa.
set -euo pipefail
cd "$(dirname "$0")"

MYIP="$(curl -4 -s https://ifconfig.me)/32"
terraform destroy -var="my_ip=$MYIP" -auto-approve
rm -f kubeconfig
echo ">> Da destroy. Kiem tra Console khong con resource k8s-tf-hung-*."
