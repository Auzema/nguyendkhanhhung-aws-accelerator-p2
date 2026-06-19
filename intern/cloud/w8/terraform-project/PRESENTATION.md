# Bài present: K8s on AWS — Terraform 1-Click

> Kịch bản 5–7 phút + Q&A. Đọc từ trên xuống là thành bài nói.
> Mở kèm `diagram.html` để chỉ vào hình khi nói.

---

## 1. Mở đầu (30 giây)

> "Project của em dựng một web app chạy trên Kubernetes **self-managed** trên AWS,
> toàn bộ bằng Infrastructure as Code. Gõ **một lệnh** `./deploy.sh` là từ con số 0
> ra một trang web sống trên Internet; `./destroy.sh` là dọn sạch không sót gì."

Một câu chốt vấn đề: **không click tay trên Console** — mọi thứ là code, tái tạo
được, có lịch sử, review được.

---

## 2. Các "nhân vật" (1 phút — dùng ví dụ đời thường)

| Thành phần | Vai trò | Ví dụ đời thường |
|---|---|---|
| **Terraform** | Đọc file `.tf` mô tả "muốn gì", tự tính thứ tự và dựng | Bản vẽ + đội thi công: mình vẽ nhà, đội tự biết đổ móng trước xây tường sau |
| **VPC + subnet + IGW** | Mạng riêng trên AWS | Khu đất riêng, chia 2 lô, có cổng ra đường lớn |
| **EC2 + Elastic IP** | 1 máy chủ, IP public **cố định** | Căn nhà có **số nhà không bao giờ đổi** |
| **minikube** | Cụm Kubernetes 1 node chạy **bên trong** EC2 | Xưởng sản xuất đặt trong nhà |
| **ALB** | Cổng vào duy nhất từ Internet, port 80 | Lễ tân: khách chỉ gặp lễ tân, không ai vào thẳng kho |
| **socat** (2 cái) | Chuyển tiếp cổng từ host EC2 vào trong minikube | Người đưa thư giữa cổng nhà và phòng trong |
| **nginx ×2 + ConfigMap** | App: trang HTML + video nhúng sẵn | 2 nhân viên phục vụ cùng đọc chung 1 tập tài liệu |

**5 Terraform provider, mỗi cái đúng 1 việc:**
`aws` (dựng hạ tầng) · `tls` (sinh SSH key RSA 4096) · `local` (ghi key ra `.pem`)
· `null` (SSH chờ cụm + scp kubeconfig) · `kubernetes` (deploy app vào cụm).

---

## 3. Mọi thứ NỐI nhau thế nào (2 phút — phần ăn điểm)

Đây là chỗ thể hiện hiểu sâu. 5 mối nối quan trọng:

**(a) Dependency graph — Terraform tự biết thứ tự.**
Subnet tham chiếu `aws_vpc.main.id` → Terraform hiểu "VPC trước, subnet sau".
Không ghi tay thứ tự. Chỗ nào không có tham chiếu trực tiếp thì ép bằng
`depends_on` — ví dụ EC2 `depends_on` route table association (vì script boot
cần kéo package từ Internet → route ra IGW phải sẵn sàng trước khi máy bật).

**(b) EIP được "tiêm" vào script boot.**
`user_data = templatefile("user_data.sh.tpl", { eip = aws_eip.web.public_ip })`
→ minikube khởi động với `--apiserver-ips=EIP` → **cert TLS sinh đúng cho IP cố
định đó**. Đây là lý do cần EIP: cert + kubeconfig đều pin theo IP; IP nhảy là
mất kết nối cụm.

**(c) Security Group nối bằng THAM CHIẾU, không phải IP.**
SG của EC2 mở port 30080 cho `security_groups = [SG của ALB]` — nghĩa là
"chỉ ai đeo thẻ ALB mới được vào", không phải "mở cho dải IP nào đó".
Khách không thể gõ thẳng `EC2:30080`, bắt buộc đi qua lễ tân.

**(d) Cây cầu giữa 2 thế giới: null_resource + kubeconfig.**
Thế giới AWS (Terraform dựng) và thế giới Kubernetes (app chạy) nối nhau bằng
1 file: `null_resource` SSH vào EC2, **chờ** cụm sẵn sàng (file READY xuất hiện),
rồi **scp kubeconfig về laptop**. Provider `kubernetes` đọc file đó để deploy app
qua `https://EIP:8443`.

**(e) Hợp đồng "30080" xuyên suốt.**
Cùng 1 con số cổng được hẹn trước ở 4 chỗ: Service NodePort `30080` → socat
listen `30080` → target group port `30080` → SG mở `30080`. Lệch 1 chỗ là đứt
chuỗi. (Mentor hỏi "sao chọn 30080?" → nằm trong dải NodePort hợp lệ 30000–32767.)

---

## 4. Luồng BUILD — vì sao 2 phase (1.5 phút)

> Chỉ vào sequence "Provision" trong diagram.

**Câu hỏi vàng mentor sẽ hỏi: "Sao không apply 1 lần?"**

Provider `kubernetes` cần file `./kubeconfig` tồn tại **ngay lúc `plan`** —
nhưng file đó chỉ sinh ra **sau khi** EC2 boot xong + minikube dựng xong + scp về.
Terraform không cho provider config phụ thuộc resource chưa tạo → con gà quả trứng.

**Giải: 2 phase, gói trong `deploy.sh` nên người dùng vẫn thấy 1 lệnh:**

1. **Phase 1** — `terraform apply -target=null_resource.kubeconfig`:
   dựng VPC → EIP → EC2 (boot tự cài Docker, swap 2GB, minikube, 2 socat)
   → SSH chờ READY → scp kubeconfig về.
2. **Phase 2** — `terraform apply` đầy đủ:
   giờ kubeconfig đã có lúc plan → tạo ALB + target group, rồi provider
   `kubernetes` deploy ConfigMap + Deployment (nginx ×2) + Service.

Ví dụ đời thường: **xây xong nhà mới có chìa khóa; có chìa khóa rồi mới vào
trang trí nội thất.** Không thể vừa vẽ móng vừa kê sofa trong cùng một hợp đồng.

Lưu ý kể thêm: minikube **không phải Terraform cài** — EC2 tự cài lúc boot qua
`user_data` (cloud-init). Terraform chỉ deploy **app** vào cụm.

---

## 5. Luồng USE — một khách mở trang (1 phút)

> Chỉ vào sequence "Live request".

```
Khách → ALB:80 → EC2:30080 → socat-app → Service NodePort → 1 trong 2 pod nginx
      → nginx đọc index.html + video từ ConfigMap → trả 200 OK → video autoplay
```

3 ý nhấn:
- **ALB không biết pod.** Nó chỉ thấy "EC2:30080 sống hay chết" (health check `/`).
  Chọn pod nào là việc của Service bên trong cụm.
- **Vì sao cần socat:** NodePort của minikube bind trên IP container
  (`192.168.49.2`) — không ra tới host EC2. socat bắc cầu host → container.
- **2 đường tách biệt:** đường khách (ALB:80→30080, public) và đường admin
  (SSH 22 + apiserver 8443, khóa đúng IP máy mình). Khách không bao giờ chạm
  được apiserver.

---

## 6. Bảo mật (45 giây)

- Internet chỉ mở đúng **1 cổng: ALB:80**.
- App 30080: chỉ nhận từ **SG của ALB** (tham chiếu SG).
- SSH 22 + apiserver 8443: chỉ cho **IP máy mình** (`var.my_ip` — deploy.sh tự lấy).
- SSH key do `tls` sinh mỗi lần deploy, file `.pem` quyền 0400.
- `.gitignore` chặn `*.tfstate*` (state chứa **private key plaintext!**),
  `*.pem`, `kubeconfig` — không bao giờ commit.

---

## 7. Pros & Cons nếu chạy THẬT ngoài đời (1.5 phút — phần "trưởng thành")

### Pros
| Điểm mạnh | Vì sao |
|---|---|
| **Tái tạo 100%** | Cả hệ thống là code; máy mới clone repo + `./deploy.sh` là ra y hệt. Cháy môi trường → dựng lại trong ~10 phút |
| **Rẻ** | 1 EC2 t4g (~$25/tháng) + ALB (~$18/tháng). EKS riêng control plane đã ~$73/tháng |
| **Lên/xuống 1 lệnh** | Lab, demo, môi trường tạm: dùng xong destroy, không rò chi phí |
| **Hiểu sâu** | Self-managed = tự lo cert, kubeconfig, networking → học được internals mà EKS giấu đi |
| **Bảo mật có lớp** | 1 cổng public duy nhất, SG nối bằng tham chiếu, key sinh tự động |

### Cons (nói chủ động = ghi điểm)
| Điểm yếu | Hậu quả thật | Ngoài đời sẽ làm |
|---|---|---|
| **SPOF — 1 EC2, 1 node** | EC2 chết = cả site chết. ALB đứng 2 AZ nhưng target chỉ 1 máy 1 AZ | Auto Scaling Group nhiều AZ, hoặc EKS managed node group |
| **minikube ≠ production** | 1 node, không HA control plane, không cloud integration | EKS / kubeadm HA |
| **HTTP trần** | Không mã hóa, không chống bot | HTTPS qua ACM + listener 443, WAF |
| **socat relay** | Thêm 1 điểm gãy không ai giám sát; chết là mất cả app lẫn API | CNI/ingress chuẩn, hoặc node networking thật |
| **State local + chứa secret** | Mất laptop = mất state + lộ key; không làm việc nhóm được (không lock) | Remote state S3 mã hóa + DynamoDB lock |
| **Provisioner SSH/scp** | Mạng rớt giữa chừng → state lệch, phải gỡ tay | Đẩy logic vào image/user_data, hoặc GitOps |
| **Media trong ConfigMap** | Cap 1MB — video 643KB vừa lọt, file thật thì tắc | S3 + CDN (CloudFront) |
| **Không autoscale, không monitoring** | Tải tăng là nghẽn; chết không ai biết | HPA + metrics-server; Prometheus/Grafana |

> Câu chốt phần này: "Em biết rõ đây là kiến trúc **lab để học internals** —
> lên production em sẽ đổi X, Y, Z như bảng trên. Thực tế tuần 9 em đã đi tiếp
> đúng hướng đó: GitOps bằng ArgoCD + Prometheus + canary."

---

## 8. Q&A dự phòng (đáp 1–2 câu)

- **Sao 2 phase?** → kubernetes provider cần `./kubeconfig` lúc *plan*; file chỉ có sau khi cụm dựng + scp về. `-target` phase 1, full apply phase 2.
- **Sao cần EIP?** → cert apiserver + kubeconfig pin theo IP. IP auto đổi khi stop/start → cert mismatch + kubeconfig trỏ sai → mất cụm.
- **Sao cần socat?** → NodePort/apiserver bind IP container, không ra host. socat forward host→container cho ALB và laptop.
- **Sao ALB cần 2 subnet 2 AZ?** → ràng buộc cứng của AWS (ALB phải đứng ≥2 AZ), dù target chỉ 1 EC2.
- **Sao minikube mà không EKS?** → đề yêu cầu self-managed; EKS là managed + $0.10/giờ. minikube đúng yêu cầu + free.
- **`user_data_replace_on_change` làm gì?** → AWS không cho sửa user_data máy đang chạy; mặc định Terraform stop/start (không chạy lại script). Cờ này ép tạo máy mới chạy script mới — sạch.
- **State có gì nhạy cảm?** → private key SSH plaintext (tls provider sinh) → gitignore, không commit; ngoài đời để S3 mã hóa + lock.
- **destroy có sạch không?** → Terraform xóa mọi thứ trong state theo thứ tự ngược dependency graph (EC2/ALB → subnet/IGW → VPC); `destroy.sh` xóa thêm file kubeconfig local. Không phải dọn Console tay.
- **Muốn autoscale pod?** → HPA: bật metrics-server, thêm resources.requests, tạo HPA min2/max10 theo CPU; nhớ `lifecycle ignore_changes` trên replicas để Terraform không giành với HPA.

---

## 9. Demo trực tiếp (nếu được yêu cầu)

```bash
./deploy.sh                       # ~7-10 phút; vừa chạy vừa nói tiếp
terraform output                  # alb_url / ec2_public_ip / ssh_command
# mở alb_url → trang + video chạy (chờ ~60s ALB health check)

# Trick hay: chứng minh self-healing của K8s
export KUBECONFIG=./kubeconfig
kubectl get pods                  # 2 pod web
kubectl delete pod <tên-1-pod>    # giết 1 pod
kubectl get pods                  # ReplicaSet đẻ pod mới ngay — site không sập

./destroy.sh                      # dọn sạch, nhấn "ALB tính tiền theo giờ"
```
