#!/bin/bash
# Chay 1 lan luc EC2 boot (cloud-init). Log: /var/log/user-data.log
# ${eip} duoc Terraform inject (Elastic IP co dinh) -> cert + kubeconfig khong vo khi instance doi.
set -uxo pipefail
exec > /var/log/user-data.log 2>&1

ARCH=arm64
PUBIP="${eip}"   # Elastic IP - co dinh, KHONG lay tu IMDS (auto IP doi khi stop/start)

# --- Cai goi ---
dnf update -y
dnf install -y docker socat
systemctl enable --now docker
usermod -aG docker ec2-user   # minikube docker driver KHONG chay duoc voi root

# --- 2GB swap: t4g.small chi 2GB RAM, minikube an 1800 -> host can dem ---
if [ ! -f /swapfile ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# --- kubectl (arm64) ---
KVER=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -sLO "https://dl.k8s.io/release/$${KVER}/bin/linux/$${ARCH}/kubectl"
install -m0755 kubectl /usr/local/bin/kubectl

# --- minikube (arm64) ---
curl -sLO "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-$${ARCH}"
install -m0755 "minikube-linux-$${ARCH}" /usr/local/bin/minikube

# --- Khoi dong cum (chay nhu ec2-user, KHONG root) ---
# --apiserver-ips=EIP -> cert apiserver hop le cho EIP -> laptop kubectl duoc
sudo -iu ec2-user minikube start \
  --driver=docker \
  --apiserver-ips="$${PUBIP}" \
  --memory=1800 --cpus=2

# --- Lay cong apiserver (docker driver publish 127.0.0.1:<port> ngau nhien) + IP minikube ---
APIPORT=$(sudo -iu ec2-user kubectl config view --minify \
  -o jsonpath='{.clusters[0].cluster.server}' | sed 's#.*:##')
MKIP=$(sudo -iu ec2-user minikube ip)

# --- socat #1: ALB -> app NodePort ---
cat >/etc/systemd/system/socat-app.service <<EOF
[Unit]
Description=forward host 30080 to minikube NodePort
After=network-online.target
[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:30080,fork,reuseaddr TCP:$${MKIP}:30080
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# --- socat #2: laptop -> apiserver ---
cat >/etc/systemd/system/socat-api.service <<EOF
[Unit]
Description=forward host 8443 to minikube apiserver
After=network-online.target
[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:8443,fork,reuseaddr TCP:$${MKIP}:$${APIPORT}
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now socat-app socat-api

# --- kubeconfig "externalized" cho kubernetes provider tu laptop ---
sudo -iu ec2-user kubectl config view --flatten --minify > /home/ec2-user/kubeconfig.ext
sed -i "s#server: https://.*#server: https://$${PUBIP}:8443#" /home/ec2-user/kubeconfig.ext
chmod a+r /home/ec2-user/kubeconfig.ext

# --- Co bao "xong" ---
touch /home/ec2-user/READY
