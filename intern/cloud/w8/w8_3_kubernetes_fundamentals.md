# Tài Liệu Chuyên Sâu: Nền Tảng Kubernetes & Điều Phối Container

---

## Phần 1: Câu Chuyện Thực Tế — Hành Trình Thay Đổi Tư Duy Hạ Tầng Từ EC2 Sang Kubernetes

Sau khi đã làm chủ việc tự động hóa cấp phát tài nguyên trên AWS bằng Terraform, nhóm dự án X-Shop tiến hành triển khai ứng dụng thương mại điện tử trực tiếp lên các máy chủ ảo EC2 (Elastic Compute Cloud — dịch vụ cung cấp máy chủ ảo có thể thay đổi kích thước của AWS). Mọi thứ ban đầu hoạt động suôn sẻ, nhưng khi lưu lượng người dùng tăng cao và các tính năng mới được bổ sung liên tục, mô hình này bắt đầu bộc lộ những điểm yếu chí mạng:

1.  **Vấn đề phục hồi hệ thống chậm (Downtime):** Mỗi khi ứng dụng bị lỗi tràn bộ nhớ (Memory Leak) hoặc treo cứng (Deadlock), kỹ sư vận hành (SRE - Site Reliability Engineering) phải thủ công thiết lập kết nối từ xa an toàn (SSH - Secure Shell) vào từng máy chủ EC2 để khởi động lại dịch vụ. Quá trình này không thể thực hiện theo thời gian thực 24/7, dẫn đến thời gian gián đoạn dịch vụ kéo dài.
2.  **Khả năng mở rộng (Scaling) kém hiệu quả:** Trong những dịp sự kiện giảm giá, số lượng máy chủ cần được nhân bản nhanh chóng để đáp ứng tải. Tuy nhiên, việc khởi động một máy chủ ảo EC2 mới, từ việc tải hệ điều hành, cài đặt môi trường, đến khởi động ứng dụng mất hàng chục phút, khiến hệ thống không thể phản ứng kịp với lượng truy cập đột biến.
3.  **Quản lý cấu hình cứng (Hardcoded Configuration):** Các thông tin nhạy cảm như chuỗi kết nối cơ sở dữ liệu (Database Connection String) hay khóa bảo mật giao diện lập trình ứng dụng (API Key - Application Programming Interface Key) bị đóng gói chung với mã nguồn. Khi cần thay đổi một tham số, nhóm kỹ sư phải tiến hành quy trình đóng gói (Build) lại toàn bộ ứng dụng từ đầu.
4.  **Lỗ hổng bảo mật mạng ngang hàng (Flat Network):** Do triển khai trong cùng một mạng ảo cá nhân (VPC - Virtual Private Cloud) và thiếu sự cô lập giữa các ứng dụng, khi một máy chủ chứa dịch vụ giao diện người dùng (Frontend) bị tấn công, kẻ gian có thể di chuyển ngang (Lateral Movement) sang máy chủ chứa cơ sở dữ liệu một cách dễ dàng.

Nhận diện được những rào cản từ kiến trúc cũ, dự án quyết định áp dụng mô hình đóng gói ứng dụng (Containerization) và sử dụng **Kubernetes (K8s — nền tảng mã nguồn mở quản lý và điều phối vùng chứa container ở quy mô lớn)**. Kubernetes thay đổi hoàn toàn cách quản lý hệ thống: thay vì tương tác với từng máy chủ riêng lẻ, kỹ sư chỉ cần "khai báo" trạng thái mong muốn (Declarative State), K8s sẽ tự động điều phối, duy trì, và mở rộng ứng dụng liên tục mà không cần sự can thiệp của con người.

---

## Phần 2: Kiến Trúc Cốt Lõi Và Phương Pháp Khai Báo (Declarative Architecture)

Kubernetes hoạt động dựa trên mô hình phân tán (Distributed System) bao gồm hai thành phần chính: Khối điều khiển (Control Plane) chịu trách nhiệm đưa ra quyết định toàn cục, và các Nút xử lý (Worker Nodes) thực thi khối lượng công việc.

### 1. Phân Tích Kiến Trúc Control Plane và Worker Node
*   **API Server (Application Programming Interface Server):** Trái tim của Kubernetes. Là cổng giao tiếp duy nhất cho mọi thành phần (người dùng qua dòng lệnh, các dịch vụ nội bộ) để đọc/ghi cấu hình.
*   **etcd:** Cơ sở dữ liệu theo dạng khóa-giá trị (Key-Value Store) có tính nhất quán cao, lưu trữ toàn bộ trạng thái và cấu hình của cụm K8s.
*   **Scheduler:** Theo dõi tài nguyên (CPU, RAM) trống trên các máy chủ và quyết định đưa các ứng dụng mới vào máy chủ nào phù hợp nhất.
*   **Controller Manager:** Chạy các vòng lặp kiểm soát (Control Loops) liên tục so sánh trạng thái thực tế của hệ thống với trạng thái khai báo mong muốn, và thực hiện hành động điều chỉnh (Reconciliation) nếu có sai lệch.
*   **Kubelet (Trên Worker Node):** Tác nhân (Agent) của K8s chạy trên mỗi máy chủ vật lý/ảo, nhận lệnh từ API Server để khởi tạo và theo dõi sức khỏe của các container.
*   **Kube-proxy (Trên Worker Node):** Quản lý các quy tắc định tuyến mạng (Network Rules) trên mỗi máy chủ để cho phép giao tiếp giữa các dịch vụ trong cụm K8s.

### 2. Đơn Vị Triển Khai Nhỏ Nhất: Pod (Nhóm Vùng Chứa)
Trong Kubernetes, chúng ta không trực tiếp quản lý từng container, mà quản lý **Pod**. Pod là một lớp bọc logic (Logical Host) chứa một hoặc nhiều container có liên hệ mật thiết với nhau. Các container trong cùng một Pod chia sẻ chung một không gian mạng (Network Namespace), chung một địa chỉ IP nội bộ, và có thể truy cập chung không gian lưu trữ (Volumes).

*Ví dụ khai báo triển khai một Backend Application bằng tệp YAML (YAML Ain't Markup Language - định dạng tuần tự hóa dữ liệu dạng văn bản thân thiện với con người):*

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-deployment
  labels:
    app: xshop
spec:
  replicas: 3 # Khai báo hệ thống cần duy trì chính xác 3 bản sao của Pod
  selector:
    matchLabels:
      component: backend
  template: # Khu vực định nghĩa chi tiết cho Pod
    metadata:
      labels:
        component: backend
    spec:
      containers:
      - name: nodejs-app
        image: repository/backend:v1.2.0
        ports:
        - containerPort: 3000
        resources: # Giới hạn và Đảm bảo tài nguyên phần cứng
          requests:
            cpu: "100m" # Yêu cầu đảm bảo tối thiểu 0.1 CPU core
            memory: "256Mi"
          limits:
            cpu: "500m" # Không cho phép vượt quá 0.5 CPU core
            memory: "512Mi"
```

---

## Phần 3: Quản Lý Lưu Lượng Và Định Tuyến Mạng Cùng Service

Bản chất của Pod trong Kubernetes là "phù du" (Ephemeral). Chúng có thể bị xóa đi và tạo lại liên tục khi nâng cấp phiên bản, ứng dụng lỗi, hoặc máy chủ chủ quản bị hỏng. Khi một Pod mới sinh ra, nó sẽ nhận một địa chỉ IP hoàn toàn mới. Điều này gây ra thách thức lớn: Làm sao các thành phần khác có thể tìm thấy nhau nếu địa chỉ IP liên tục thay đổi?

K8s giải quyết vấn đề này bằng đối tượng **Service**. Service tạo ra một điểm kết nối trừu tượng với một địa chỉ IP cố định (ClusterIP) và tên miền nội bộ (Internal DNS - Domain Name System), đóng vai trò như một bộ cân bằng tải nội bộ (Internal Load Balancer) định tuyến lưu lượng vào danh sách các Pod đang hoạt động phía sau (dựa trên bộ lọc Label Selector).

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  selector:
    component: backend # Tự động phát hiện và liên kết với các Pod mang nhãn này
  ports:
  - protocol: TCP
    port: 80         # Cổng tiếp nhận lưu lượng đại diện của Service
    targetPort: 3000 # Cổng thực tế của tiến trình đang chạy bên trong Pod
  type: ClusterIP    # Định nghĩa loại mạng cung cấp
```

### Phân Loại Các Kiểu Mạng Kubernetes Service:
1.  **ClusterIP (Mặc định):** Cung cấp IP ảo chỉ truy cập được từ bên trong cụm K8s. Đây là mức độ bảo mật mạng tiêu chuẩn cho các dịch vụ Back-end và cơ sở dữ liệu.
2.  **NodePort:** Mở một cổng vật lý cụ thể (phạm vi từ 30000 - 32767) trên mọi Nút (Worker Node) trong hệ thống. Lượng truy cập gửi tới `NodeIP:NodePort` sẽ được tự động chuyển hướng vào Service. Thích hợp cho môi trường phát triển (Development).
3.  **LoadBalancer:** Yêu cầu một Bộ cân bằng tải vật lý từ nhà cung cấp Đám mây (Cloud Provider như AWS ALB/NLB). Mở hệ thống cho lượng truy cập thực tế từ Internet đổ trực tiếp vào Service.
4.  **ExternalName:** Phân giải và chuyển hướng yêu cầu gọi nội bộ sang một tên miền bên ngoài (Ví dụ: một Cơ sở dữ liệu AWS RDS - Relational Database Service), giúp mã nguồn không bị phụ thuộc vào tên miền bên ngoài và có thể dễ dàng chuyển đổi sau này.
5.  **Headless Service:** Thiết lập tham số `clusterIP: None`. Service sẽ không đại diện thay các Pod, mà thay vào đó sẽ trả về danh sách toàn bộ các địa chỉ IP thực tế của từng Pod. Rất quan trọng khi triển khai các hệ thống lưu trữ có trạng thái (Stateful Database Clusters) cần các Pod đồng bộ dữ liệu giao tiếp điểm-điểm (Peer-to-peer).

---

## Phần 4: Đảm Bảo Tính Khả Dụng Với Probes (Kiểm Tra Sức Khỏe)

Hệ thống điều phối sẽ vô dụng nếu nó không nhận biết được tình trạng của ứng dụng. K8s cung cấp cơ chế **Probes** để tác nhân Kubelet có thể liên tục thăm dò, từ đó đưa ra quyết định Khởi động lại (Restart) hoặc Cách ly (Isolate) container.

```yaml
        # (Nằm trong mục khai báo Container của Pod)
        startupProbe:
          httpGet:
            path: /health/startup
            port: 3000
          failureThreshold: 30
          periodSeconds: 10
        
        livenessProbe:
          httpGet:
            path: /health/live
            port: 3000
          initialDelaySeconds: 15
          periodSeconds: 20
        
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 3000
          periodSeconds: 5
```

### Các Cơ Chế Kiểm Tra Cốt Lõi:
1.  **Startup Probe (Thăm dò Khởi động):** Thiết kế chuyên biệt cho các ứng dụng mất nhiều thời gian để khởi tạo ban đầu (ví dụ: ứng dụng Java Spring Boot hoặc quá trình nạp cache). Các Probe khác sẽ bị vô hiệu hóa cho đến khi Probe này thành công. Khi quá số lần cho phép (`failureThreshold`), container sẽ bị buộc dừng và khởi động lại.
2.  **Liveness Probe (Thăm dò Sự Sống):** Trả lời cho câu hỏi: *"Ứng dụng còn khả năng xử lý không hay đã bị đóng băng (Deadlock)?"* Nếu Probe này thất bại nhiều lần liên tiếp, K8s sẽ tiến hành quá trình Tự phục hồi (Self-Healing) bằng cách hủy bỏ container và tạo phiên bản mới thay thế.
3.  **Readiness Probe (Thăm dò Sẵn Sàng):** Trả lời cho câu hỏi: *"Ứng dụng đã sẵn sàng nhận kết nối mạng hay đang bị quá tải (Overloaded)?"* Nếu Probe thất bại, K8s không khởi động lại container, mà chỉ gỡ bỏ IP của Pod ra khỏi danh sách định tuyến của Service, đảm bảo khách hàng không bị dẫn vào một máy chủ đang gặp sự cố.

---

## Phần 5: Phân Tách Môi Trường Bằng ConfigMap & Secret

Theo quy chuẩn của Mô hình 12 Yếu Tố (Twelve-Factor App Methodology), thông tin cấu hình (Configuration) phải được tách biệt hoàn toàn khỏi mã nguồn đóng gói (Codebase). K8s hiện thực hóa điều này qua hai đối tượng lưu trữ chuyên biệt.

### 1. ConfigMap (Cấu Hình Phi Bảo Mật)
Lưu trữ các giá trị cấu hình thông thường như đường dẫn URL, cấp độ ghi nhật ký (Log Level), cờ tính năng (Feature Flags).

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-settings
data:
  LOG_LEVEL: "info"
  MAX_CONNECTIONS: "100"
```

### 2. Secret (Cấu Hình Nhạy Cảm)
Lưu trữ mật khẩu cơ sở dữ liệu, khóa riêng tư (Private Keys), và chứng chỉ bảo mật (TLS Certificates). Tuy nhiên, một lầm tưởng nghiêm trọng là K8s tự động mã hóa Secret. Theo mặc định, dữ liệu trong Secret chỉ được **Mã hóa chuỗi 64 phân tử (Base64 Encoding)**, rất dễ dàng để dịch ngược. Kỹ sư phải thực hiện bật tính năng Mã hóa khi lưu trữ tĩnh (Encryption at Rest) ở cấp độ etcd, đồng thời phân quyền kiểm soát truy cập (RBAC - Role-Based Access Control) chặt chẽ đối với các đối tượng Secret.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  DB_PASS: "c3VwZXJzZWNyZXRwYXNzd29yZA==" # Giá trị đã được mã hóa Base64
```

### Truyền Cấu Hình Vào Ứng Dụng:
Cấu hình có thể được đưa vào Pod thông qua việc gán vào **Biến môi trường (Environment Variables)** (thường gặp khi kết nối Database), hoặc **Gắn tệp tin (Volume Mounts)** (thường gặp khi truyền file chứng chỉ Nginx/SSL).

---

## Phần 6: An Ninh Mạng Nội Bộ Với Network Policies (Mô Hình Zero Trust)

Một trong những rủi ro bảo mật lớn nhất khi triển khai K8s là mặc định tất cả các Pod đều có thể giao tiếp hai chiều không giới hạn với bất kỳ Pod nào khác trong hệ thống. Một kẻ tấn công thỏa hiệp được tầng Frontend có thể chạy mã rà quét cổng mạng (Port Scanning) và truy xuất tự do vào tầng Database.

K8s cung cấp đối tượng **Network Policy** để thiết lập tường lửa mức siêu nhỏ (Micro-segmentation), bắt buộc hệ thống phải triển khai triết lý Không tin cậy bất cứ ai (Zero Trust Network). Để tính năng này hoạt động, cụm K8s phải được cài đặt một Trình cắm giao diện mạng (CNI Plugin - Container Network Interface) tương thích, ví dụ như Calico hoặc Cilium.

*Ví dụ cấu hình Policy bảo vệ Cơ sở dữ liệu: Thiết lập luật chỉ cho phép truy cập đi vào (Ingress) từ những Pod thuộc tầng Backend, và từ chối mọi yêu cầu khác.*

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-db
spec:
  podSelector: # Xác định mục tiêu áp dụng chính sách
    matchLabels:
      role: database
  policyTypes:
  - Ingress # Khai báo chính sách kiểm soát luồng đi vào
  ingress:
  - from: # Danh sách các nguồn được phép
    - podSelector:
        matchLabels:
          role: backend
    ports:
    - protocol: TCP
      port: 5432 # Port của PostgreSQL
```

Bằng việc thiết lập luật chặt chẽ, ta có thể xây dựng các quy tắc an toàn bảo vệ toàn diện môi trường ứng dụng khỏi các hành vi leo thang đặc quyền.

---

## Tổng Kết: Giải Mã Các Lỗi Vận Hành Thực Tế Trong K8s

Kỹ sư khi vận hành K8s cần nắm bắt được ý nghĩa các thông báo lỗi kinh điển của hệ thống (Status codes):

*   **CrashLoopBackOff:** Tác nhân Kubelet đã khởi động container thành công, nhưng ứng dụng (Process) bên trong lại báo lỗi tự động tắt đi (Exit). Kubelet sẽ thử khởi động lại (Restart), nhưng ứng dụng tiếp tục chết, dẫn đến vòng lặp vô tận. Nguyên nhân thường là do sai đường dẫn cấu hình hoặc lỗi kết nối đầu vào chưa được xử lý trong mã nguồn. Cần dùng lệnh `kubectl logs <pod-name>` để xác định lỗi từ ứng dụng.
*   **ImagePullBackOff / ErrImagePull:** Tác nhân Kubelet không thể tải (Pull) tệp hình ảnh đóng gói (Docker Image) từ máy chủ lưu trữ (Container Registry). Nguyên nhân có thể do tên hình ảnh bị gõ sai, hoặc K8s thiếu quyền truy cập (Secret Credentials) vào các kho chứa riêng tư (Private Registry).
*   **OOMKilled (Out Of Memory Killed):** Trình quản lý hệ điều hành Linux buộc phải giết bỏ tiến trình (Container) của bạn vì ứng dụng đã tiêu thụ vượt quá mức giới hạn RAM (`limits.memory`) mà bạn đã khai báo trong YAML cấu hình. Cần kiểm tra lại mã nguồn xem có xảy ra lỗi tràn bộ nhớ không, hoặc thiết lập nâng giới hạn RAM trong giới hạn tài nguyên của Pod.
