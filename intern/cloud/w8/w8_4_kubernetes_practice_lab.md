# Tài Liệu Chuyên Sâu: Thực Hành Kubernetes & Triển Khai Lab "Mini K8s Platform" trên Minikube

---

## Phần 1: Câu Chuyện Thực Tế — Đưa Ứng Dụng Từ Giấy Lên Môi Trường Cục Bộ (Local)

Sau khi hiểu rõ các lý thuyết cốt lõi về Pod, Service, Probes và Network Policies, Nam và Hoa (nhóm X-Shop) phải đối mặt với thử thách tiếp theo từ Mentor Nghĩa: 
> *"Lý thuyết rất tốt, nhưng hạ tầng không chạy trên giấy. Hai em hãy sử dụng máy cá nhân để thiết lập một cụm Kubernetes thu nhỏ, tự động hóa việc mở rộng (Scaling) khi có tải, phơi bày ứng dụng ra ngoài an toàn qua một tên miền duy nhất thay vì IP rác, và triển khai thành công toàn bộ hệ thống X-Shop (Frontend, Backend, Database)."*

Họ không thể thuê máy chủ AWS EC2 ngay lập tức vì chi phí đắt đỏ trong quá trình thử nghiệm. Giải pháp lý tưởng nhất lúc này là **Minikube** — một công cụ giả lập toàn bộ hệ thống Kubernetes phức tạp chỉ trong một máy ảo (hoặc Docker container) chạy ngay trên máy tính cá nhân.

---

## Phần 2: Thiết Lập Cụm Kubernetes Cục Bộ (Minikube)

Để bắt đầu, kỹ sư cần chuẩn bị **Docker Desktop** (môi trường ảo hóa), **kubectl** (công cụ dòng lệnh tương tác K8s API) và **Minikube**.

### 1. Khởi chạy và Quản lý Minikube
Khởi chạy một cụm Kubernetes 1-Node (vừa làm Control Plane, vừa làm Worker Node) trên máy tính:
```bash
# Khởi tạo cụm với tài nguyên chỉ định (ví dụ: 4 CPU, 4GB RAM)
minikube start --cpus 4 --memory 4096 --driver=docker

# Kiểm tra trạng thái của các thành phần hệ thống
kubectl get nodes
minikube status
```

### 2. Tiện ích mở rộng của Minikube (Addons)
Minikube cung cấp sẵn các trình cắm (addons) để kích hoạt các tính năng nâng cao mà bình thường phải cấu hình rất thủ công trên Cloud:
```bash
# Kích hoạt Metrics Server (Bắt buộc để K8s thu thập CPU/RAM phục vụ Autoscaling)
minikube addon enable metrics-server

# Kích hoạt Ingress Controller (Nginx) để điều hướng HTTP traffic
minikube addon enable ingress

# Kích hoạt giao diện quản lý trực quan K8s Dashboard
minikube dashboard
```

---

## Phần 3: Scaling — Kỹ Thuật Tự Động Mở Rộng Linh Hoạt

Mô hình hiện tại của Nam và Hoa thiết lập `replicas: 3` (chạy cố định 3 Pod). Nhưng vào lúc 2 giờ sáng khi không ai truy cập, việc giữ 3 Pod là lãng phí tài nguyên. Ngược lại, vào dịp Sale 6/6, 3 Pod là không đủ.

Kubernetes cung cấp tính năng **HPA (Horizontal Pod Autoscaler — Bộ tự động mở rộng Pod theo chiều ngang)**. HPA liên tục đo lường mức độ sử dụng CPU/RAM thông qua `metrics-server` và quyết định tăng hoặc giảm số lượng Pod theo thời gian thực.

### Cấu hình HPA (Autoscaling)
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend-deployment # Nhắm mục tiêu vào Deployment quản lý Backend
  minReplicas: 1             # Số lượng Pod tối thiểu vào ban đêm
  maxReplicas: 10            # Số lượng Pod tối đa khi bùng nổ tải
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70 # Nếu CPU trung bình của các Pod vượt quá 70%, K8s sẽ tạo thêm Pod mới
```

*Bài học xương máu:* Để HPA hoạt động, bạn **bắt buộc** phải khai báo `resources.requests` (yêu cầu tài nguyên) cho mọi container trong Deployment, nếu không K8s sẽ không biết đâu là mốc 100% để tính toán mức 70%.

---

## Phần 4: Networking Nâng Cao — Ingress Controller

Ở phần cơ bản, chúng ta dùng Service loại `LoadBalancer` hoặc `NodePort` để phơi bày ứng dụng ra ngoài. Tuy nhiên:
*   Nếu dùng `LoadBalancer` trên AWS: Mỗi Service sẽ ngốn tiền để tạo ra 1 con Load Balancer vật lý (ví dụ có 5 APIs thì phải trả tiền cho 5 Load Balancers).
*   Nếu dùng `NodePort`: Người dùng phải gõ cổng rườm rà (ví dụ: `http://xshop.com:31254`).

**Ingress Controller** là giải pháp tối ưu. Ingress hoạt động ở Lớp 7 (Application Layer), cung cấp một điểm vào (Entrypoint) duy nhất (chỉ tốn 1 Load Balancer). Từ điểm vào đó, Ingress dùng quy tắc dẫn đường (Routing Rules) để phân loại truy cập theo tên miền (Host) hoặc đường dẫn (Path).

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: xshop-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: / # Cấu hình tùy biến của Nginx
spec:
  rules:
  - host: api.xshop.local # Cấu hình tên miền ảo trên máy
    http:
      paths:
      - path: /v1/users
        pathType: Prefix
        backend:
          service:
            name: user-service # Định tuyến yêu cầu tới User Service
            port: 
              number: 80
      - path: /v1/products
        pathType: Prefix
        backend:
          service:
            name: product-service # Định tuyến yêu cầu tới Product Service
            port: 
              number: 80
```
*Lưu ý trên Minikube:* Do Minikube chạy trong mạng riêng ảo, để truy cập được Ingress bằng IP của máy tính cá nhân, bạn cần mở luồng mạng ảo (Tunnel):
```bash
minikube tunnel
# Gõ mật khẩu quản trị máy tính để minikube ánh xạ IP vào card mạng của bạn
```

---

## Phần 5: Lab Thực Tế — Xây Dựng "Mini K8s Platform"

Đây là kiến trúc Lab cuối tuần W8 mà nhóm cần hoàn thành:
1.  **Lớp Lưu Trữ (Stateful):** Triển khai MongoDB. Sử dụng Deployment kèm `Volume` hoặc `StatefulSet`. Cần một Service `ClusterIP` và `Secret` chứa mật khẩu ROOT.
2.  **Lớp Logic (Backend):** Triển khai NodeJS App. Cần mount `ConfigMap` chứa URL MongoDB và `Secret` chứa mật khẩu. Cấu hình Liveness/Readiness Probes để đảm bảo chỉ nhận traffic khi đã kết nối DB thành công. Cài đặt HPA (min: 2, max: 5) với CPU target 80%.
3.  **Lớp Giao Diện (Frontend):** Triển khai React/Nginx.
4.  **Lớp Định Tuyến Mạng (Ingress):** Cấu hình Ingress dẫn đường tên miền `xshop.local` đến Frontend, và `api.xshop.local` đến Backend.
5.  **Bảo Mật Nội Bộ (Zero Trust):** Áp dụng NetworkPolicy cấm tất cả, sau đó chỉ mở luồng từ Ingress $\rightarrow$ Frontend $\rightarrow$ Backend $\rightarrow$ MongoDB.

### Quy trình lệnh thực thi (Deployment Pipeline):
Thay vì chạy lệnh tạo từng file rải rác, K8s cho phép tổ chức cấu trúc thư mục (manifests) và triển khai hàng loạt:

```bash
# 1. Tạo các cấu hình cấu hình trước
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secrets.yaml

# 2. Tạo Database và chờ đợi
kubectl apply -f k8s/db-deployment.yaml
kubectl apply -f k8s/db-service.yaml

# 3. Tạo Backend (Kèm HPA)
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-hpa.yaml

# 4. Tạo Frontend & Ingress
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/ingress.yaml

# 5. Kiểm tra toàn hệ thống
kubectl get all -n xshop-app
```

Bằng việc vượt qua Lab này trên Minikube, học viên hoàn toàn sẵn sàng cho W9 để tự động hóa quá trình apply này bằng GitOps (ArgoCD) thay vì phải tự gõ lệnh `kubectl apply` một cách thủ công.
