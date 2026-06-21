# Tài Liệu Chuyên Sâu: Phân Phối Lũy Tiến (Progressive Delivery) - Triển Khai Canary Tự Động Hóa Với Argo Rollouts

---

## Phần 1: Câu Chuyện Thực Tế — Đợt Triển Khai Kinh Hoàng & Tầm Quan Trọng Của Việc "Thử Nghiệm Trên Diện Hẹp"

Đến tuần thứ 9, Nam và Hoa đã xây dựng được một hệ thống cực kỳ hiện đại: Cấu hình được đồng bộ tự động qua GitOps (ArgoCD) và sức khỏe hệ thống được theo dõi sát sao bằng Cảnh báo tốc độ đốt ngân sách lỗi (Burn Rate Alert). Họ tự tin thực hiện đợt phát hành phiên bản mới cho tính năng Giỏ hàng của ứng dụng X-Shop.

Tuy nhiên, một thảm họa đã xảy ra theo kịch bản không lường trước:
1.  **Cập nhật cuốn chiếu (Rolling Update) sai lầm**: Git nhận mã nguồn mới, ArgoCD kích hoạt quy trình cập nhật mặc định của nền tảng điều phối vùng chứa (Kubernetes). Sau 3 phút, toàn bộ 10 nhóm vùng chứa (Pods) phiên bản cũ bị thay thế hoàn toàn bởi 10 Pods phiên bản mới.
2.  **Lỗi logic ẩn**: Phiên bản mới vượt qua toàn bộ các bài kiểm thử tự động (Automated Tests) ở môi trường dàn dựng (Staging). Tuy nhiên, khi đối mặt với lượng truy cập cực lớn trên môi trường thực tế (Production), một lỗi logic liên quan đến việc đóng mở kết nối cơ sở dữ liệu xuất hiện.
3.  **Hệ thống tê liệt toàn diện**: Vì phiên bản lỗi đã được triển khai tới $100\%$ hệ thống, toàn bộ khách hàng trên trang web không thể thanh toán. Cảnh báo khẩn cấp (Fast Burn Rate Alert) réo vang. Nam và Hoa phải thực hiện quy trình khôi phục (Rollback) qua Git. Hệ thống mất 15 phút gián đoạn hoàn toàn, doanh thu tổn thất nặng nề.

Mentor Minh phân tích sự cố:
> *"Tại sao các em lại ném một phiên bản mới toanh vào $100\%$ khách hàng khi chưa thực sự chắc chắn nó chịu được tải thực tế? Trong kỹ thuật phần mềm hiện đại, chúng ta áp dụng **Phân phối lũy tiến (Progressive Delivery)** bằng phương pháp **Triển khai chim hoàng yến (Canary Deployment - lấy ý tưởng từ việc đem chim hoàng yến xuống mỏ than để dò khí độc)**. Ta sẽ điều hướng chỉ $5\%$ lưu lượng khách hàng vào phiên bản mới. Nếu hệ thống đo đạc phát hiện tỷ lệ lỗi tăng, quy trình phải tự động **hủy bỏ và hoàn tác (Auto-Abort & Rollback)** ngay lập tức trước khi ảnh hưởng đến $95\%$ khách hàng còn lại."*

---

## Phần 2: Kiến Trúc Argo Rollouts (Rollout CRD so với Deployment Tiêu Chuẩn)

Nền tảng Kubernetes cung cấp tài nguyên `Deployment` tiêu chuẩn, nhưng nó chỉ hỗ trợ chiến lược cập nhật cuốn chiếu (`RollingUpdate`). Nó không có khả năng phân tách lưu lượng truy cập theo tỷ lệ phần trăm chính xác, cũng không biết cách tự đánh giá số liệu.

Để giải quyết, cộng đồng Cloud Native sử dụng **Argo Rollouts** — một bộ công cụ mở rộng, cung cấp một Định nghĩa tài nguyên tùy chỉnh (CRD - Custom Resource Definition) mới tên là `Rollout`.

### 1. Sự Khác Biệt Giữa K8s Deployment và Argo Rollout

| Tiêu Chí | **Kubernetes Deployment** | **Argo Rollout** |
| :--- | :--- | :--- |
| **Chiến lược hỗ trợ** | Cuốn chiếu (`RollingUpdate`) và Thay thế toàn bộ (`Recreate`). | Hỗ trợ Canary (Tăng dần tỷ lệ phần trăm) và Xanh-Đỏ (Blue-Green - chuyển đổi môi trường tức thì). |
| **Điều hướng lưu lượng (Traffic Routing)** | Dựa vào tỷ lệ số lượng Pod (Ví dụ: 1 Pod mới và 9 Pod cũ = $10\%$ traffic). Thiếu chính xác. | Tích hợp chặt chẽ với Bộ định tuyến (Ingress Controller/Service Mesh như AWS ALB, Nginx, Istio) để điều hướng theo tỷ lệ phần trăm chính xác ở tầng ứng dụng (Lớp 7). |
| **Trí thông minh đánh giá** | Mù lòa (Blind). Chỉ cần Pod báo cáo chạy thành công là nó đè hết bản cũ. | Thông minh. Gọi truy vấn API sang hệ thống giám sát (Prometheus, Datadog) để đánh giá chất lượng phiên bản mới theo thời gian thực. |
| **Khả năng tự hoàn tác (Auto-Rollback)** | Không có. SRE phải tự can thiệp khi hệ thống sập. | Tự động hạ lưu lượng về $0\%$ và hoàn tác ngay khi chỉ số vi phạm ngưỡng cho phép. |

### 2. Sơ Đồ Kiến Trúc Canary
```text
           [ Khách Hàng Truy Cập ]
                    │
                    ▼
          [ AWS ALB Ingress ]
            /                \
(90% Lưu lượng)          (10% Lưu lượng)
         /                      \
        ▼                        ▼
[ Dịch vụ Ổn định ]        [ Dịch vụ Canary ]
  (Stable Service)           (Phiên bản mới)
        │                        │
        ▼                        ▼ (Sinh ra số liệu)
  [ Các Pod Cũ ]            [ Các Pod Mới ]
                                 │
                                 ▼ (Thu thập dữ liệu)
                           [ Prometheus ]
                                 │
                                 ▼ (Truy vấn tự động)
                         [ AnalysisTemplate ] ──► TỐT? ──► Tăng lên 50%
                                 │
                                 └──► LỖI? ──► AUTO-ABORT (Hủy bỏ & Hoàn tác về 0%)
```

---

## Phần 3: Trái Tim Của Tự Động Hóa — Mẫu Phân Tích (AnalysisTemplate)

Để Argo Rollouts biết được phiên bản mới chạy tốt hay tệ, ta phải định nghĩa các quy tắc truy vấn dữ liệu thông qua đối tượng **`AnalysisTemplate`**. 

Đối tượng này chứa các câu lệnh PromQL (Prometheus Query Language - ngôn ngữ truy vấn của Prometheus), liên tục chạy lặp lại trong suốt quá trình triển khai Canary để kiểm tra Mục tiêu chất lượng dịch vụ (SLO - Service Level Objective).

### Khai báo AnalysisTemplate Mẫu (`canary-analysis.yaml`):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: xshop-canary-success-rate
  namespace: xshop-app
spec:
  metrics:
  - name: error-rate-check
    interval: 1m # Khoảng cách giữa các lần chạy kiểm tra là 1 phút
    failureLimit: 2 # Cho phép hệ thống vi phạm tối đa 2 lần. Lần thứ 3 sẽ kích hoạt Auto-Abort.
    # Điều kiện thành công: Tỷ lệ yêu cầu LỖI phải thấp hơn 1%
    successCondition: result[0] < 0.01 
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc.cluster.local:9090
        # Truy vấn PromQL chỉ lấy dữ liệu của phiên bản Canary mới
        query: |
          sum(rate(http_requests_total{status=~"5..", pod=~"{{args.pod-hash}}.*"}[1m]))
          /
          sum(rate(http_requests_total{pod=~"{{args.pod-hash}}.*"}[1m]))
```

---

## Phần 4: Thiết Lập Chiến Lược Rollout Tích Hợp Auto-Abort

Thay vì file `deployment.yaml` truyền thống, ta cấu hình `Rollout` để chia nhỏ quá trình phát hành thành các bước (Steps). Ở mỗi bước, ta thiết lập thời gian chờ (Pause) và gắn kèm quá trình phân tích (Analysis).

### Khai Báo Rollout Chuyên Sâu (`backend-rollout.yaml`):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: backend-rollout
  namespace: xshop-app
spec:
  replicas: 10
  strategy:
    canary:
      # Định nghĩa các dịch vụ mạng để Bộ định tuyến (Ingress) biết đường chia lưu lượng
      stableService: backend-stable
      canaryService: backend-canary
      trafficRouting:
        alb:
          ingress: xshop-ingress
          servicePort: 80
      
      # Kịch bản từng bước triển khai
      steps:
      - setWeight: 5 # Bước 1: Điều hướng 5% lưu lượng cho bản Canary
      - pause:
          duration: 5m # Bước 2: Chờ 5 phút để hệ thống sinh ra đủ dữ liệu (Metrics)
      
      # Bước 3: Kích hoạt quá trình phân tích song song
      - analysis:
          templates:
          - templateName: xshop-canary-success-rate
          args:
          - name: pod-hash
            valueFrom:
              podTemplateHashValue: Latest # Truyền động mã băm của Pod mới vào PromQL
      
      - setWeight: 50 # Bước 4: Nếu phân tích vượt qua, tăng lên 50% lưu lượng
      - pause:
          duration: 10m # Bước 5: Chờ thêm 10 phút để kiểm tra độ ổn định dưới tải lớn
      
      # Bước 6: Hoàn tất, tự động đẩy lên 100% nếu không có lỗi nào phát sinh
```

---

## Phần 5: Tích Hợp Burn Rate Vào Tiêu Chí Hủy Bỏ (Abort Criteria)

Một sai lầm phổ biến khi chạy Canary là chỉ đo lường tỷ lệ lỗi của bản thân nhóm Pod Canary. Điều gì xảy ra nếu phiên bản mới làm cạn kiệt tài nguyên của cơ sở dữ liệu chung, khiến cho cả các Pod cũ (Stable) cũng bị chết lây (Cascade Failure)?

Để áp dụng chuẩn mực của Kỹ sư vận hành độ tin cậy (SRE - Site Reliability Engineering), Mentor Minh yêu cầu nhóm phải bổ sung việc kiểm tra **Cảnh báo tốc độ đốt ngân sách (Burn Rate Alert)** toàn hệ thống vào `AnalysisTemplate`.

### Luồng Tích Hợp Burn Rate Đỉnh Cao:
1.  **Lắng nghe toàn cục**: `AnalysisTemplate` không chỉ truy vấn lỗi của riêng Canary, mà còn truy vấn cảnh báo `FastBurnRate_PageSRE` từ cấu hình ở bài Observability.
2.  **Phản ứng tức thì**: Nếu phiên bản Canary làm hệ thống chung bị vi phạm tốc độ đốt ngân sách (ví dụ hệ số $> 14.4\text{x}$), quá trình phân tích sẽ lập tức trả về cờ Thất bại (Fail).
3.  **Cơ chế Auto-Abort bảo vệ hệ thống**:
    *   Argo Rollouts thu hồi lệnh tăng trọng số.
    *   Lập tức trả trọng lượng điều hướng lưu lượng của bản Canary về $0\%$ (Hoàn tác $100\%$ về bản Stable).
    *   Xóa bỏ các Pod Canary lỗi một cách cô lập, trong khi khách hàng không hề cảm nhận được sự cố gián đoạn nhờ bản Stable vẫn đứng vững.
    *   Đánh dấu trạng thái Rollout là `Degraded` trên giao diện ArgoCD để đội ngũ phát triển điều tra lỗi mà không gây hại cho khách hàng.

Bằng cách áp dụng kiến trúc Phân phối lũy tiến này, dự án X-Shop loại bỏ hoàn toàn khái niệm "Bảo trì hệ thống lúc nửa đêm", cho phép các lập trình viên tự tin phát hành mã nguồn nhiều lần trong ngày với lưới an toàn (Safety Net) tuyệt đối.
