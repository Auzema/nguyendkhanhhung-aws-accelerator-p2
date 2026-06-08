# Web App on AWS — Terraform

Final Project "Deploy a Web App on AWS". Dựng bằng Terraform:

**VPC + public/private subnet + EC2 (web) + RDS MySQL + S3 + Security Groups**, state lưu **S3 backend + DynamoDB lock**.

## Kiến trúc

```
Internet
   │ HTTP :80
   ▼
EC2 nginx (public subnet) ── EIP cố định
   │  IAM role: s3:GetObject          ── pull asset lúc boot ──▶ S3 bucket (private)
   │ :3306
   ▼
RDS MySQL (private subnet, 2 AZ) — SG chỉ cho 3306 từ EC2

State: S3 bucket (tfstate) + DynamoDB (lock)
```

| File | Vai trò |
|---|---|
| `providers.tf` | aws + tls + local |
| `backend.tf`   | state trên S3 + khoá DynamoDB |
| `network.tf`   | VPC, IGW, 2 public + 2 private subnet, route |
| `compute.tf`   | EC2 nginx, SG (80/22), EIP, IAM đọc S3 |
| `rds.tf`       | MySQL private + SG 3306 chỉ từ EC2 |
| `s3.tf`        | bucket assets (private) + upload asset |
| `variables.tf` / `outputs.tf` | input / output |
| `user_data.sh.tpl` | script boot: nginx + kéo S3 + trang web |

## Yêu cầu

- `terraform`, `aws` CLI; đã `aws configure`.

## Bước 0 — Bootstrap backend (chạy 1 lần)

Backend không nhận biến → bucket + bảng lock phải tạo TRƯỚC. Đổi tên bucket cho unique rồi chạy:

```bash
BUCKET="tf-anh-minh-tfstate-CHANGEME"   # đổi cho unique toàn cầu
REGION="us-east-1"

# 1) Bucket lưu state (bật versioning)
aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

# 2) Bảng DynamoDB làm khoá
aws dynamodb create-table --table-name tf-anh-minh-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region "$REGION"
```

Rồi sửa `backend.tf`: thay `tf-anh-minh-tfstate-CHANGEME` bằng `$BUCKET` thật.

## Bước 1 — Deploy

```bash
export TF_VAR_db_password='Doi-mat-khau-manh-8ky-tu'
./deploy.sh
```

`deploy.sh` tự lấy IP public của bạn (mở SSH chỉ cho IP đó), `terraform init` (kết nối backend) + `apply`. Xong in `web_url`.

> RDS mất ~5–10 phút tạo. Sau apply, chờ thêm ~1–2 phút cho nginx boot rồi mở `web_url`.

## Bước 2 — Destroy (tránh tốn tiền)

```bash
export TF_VAR_db_password='...'   # cùng giá trị
./destroy.sh
```

Backend (bucket tfstate + DynamoDB) không bị destroy. Xoá tay nếu muốn dọn hẳn.

## Đáp ứng yêu cầu slide

| Yêu cầu | File |
|---|---|
| VPC + public/private subnet | `network.tf` |
| EC2 web (public subnet) | `compute.tf` |
| RDS MySQL (private subnet) | `rds.tf` |
| S3 static assets | `s3.tf` |
| Security groups (chỉ traffic cần) | `compute.tf` + `rds.tf` |
| State S3 + DynamoDB lock | `backend.tf` |
