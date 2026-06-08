#!/bin/bash
# Chay 1 lan luc EC2 boot (cloud-init). Log: /var/log/user-data.log
# Cac bien ${"$"}{...} do Terraform inject (templatefile).
set -uxo pipefail
exec > /var/log/user-data.log 2>&1

# --- Cai nginx (AL2023 da co san aws-cli v2) ---
dnf install -y nginx
systemctl enable --now nginx

# --- Keo static asset tu S3 (qua IAM role, bucket private) ---
aws s3 cp "s3://${bucket}/${asset_key}" /usr/share/nginx/html/${asset_key} --region ${region}

# --- Ghi trang web ---
cat >/usr/share/nginx/html/index.html <<HTML
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>Web App on AWS - Terraform</title></head>
  <body style="font-family:sans-serif;text-align:center;margin-top:4%;background:#0f172a;color:#e2e8f0">
    <h1>Hello from EC2 on AWS</h1>
    <p>Static asset keo tu S3 bucket: <code>${bucket}</code></p>
    <p>RDS MySQL endpoint (private): <code>${rds_endpoint}</code></p>
    <video src="${asset_key}" autoplay muted loop playsinline controls
           style="max-height:60vh;border-radius:14px;box-shadow:0 8px 30px rgba(0,0,0,.5)"></video>
  </body>
</html>
HTML

# test ket noi RDS: mo duoc cong 3306 = thong
dnf install -y nc || dnf install -y nmap-ncat || true
nc -zv -w5 ${rds_endpoint} 3306 && echo "RDS 3306 OK" || echo "RDS 3306 chua san sang"

echo "user-data DONE"
