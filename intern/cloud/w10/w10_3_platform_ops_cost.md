# Tài Liệu Chuyên Sâu: Vận Hành Nền Tảng Tích Hợp (Platform Ops) & Kiểm Soát Ngân Sách Khắt Khe (Cost Guard)

---

## Phần 1: Câu Chuyện Thực Tế — Hóa Đơn Đám Mây Khổng Lồ & Sự Hỗn Loạn Khi Sập Hệ Thống

Cuối tuần thứ 10, dự án X-Shop chính thức bước vào giai đoạn thử nghiệm tải trọng (Load Testing) trên hệ thống hoàn chỉnh. Nam và Hoa cấp quyền truy cập cụm (Cluster) cho đội phát triển để họ tự do triển khai các dịch vụ mới. Chỉ hai ngày sau, thảm họa kép ập đến:

1.  **Vấn đề rò rỉ tài nguyên & Hóa đơn khổng lồ**: Một thực tập sinh viết sai vòng lặp tạo Nhóm vùng chứa (Pod) nhưng không cấu hình giới hạn RAM (Memory Limits). Hàng trăm Pod rác được sinh ra, ăn cạn kiệt toàn bộ tài nguyên của cụm máy chủ (Node). Kubernetes tự động gọi Dịch vụ tự động mở rộng cụm (Cluster Autoscaler) để mua thêm hàng chục máy chủ ảo EC2 đắt tiền trên AWS. Cuối tháng, hóa đơn AWS của dự án tăng vọt $300\%$ so với dự toán.
2.  **Sự hoảng loạn khi ứng cứu sự cố**: Đang trong tình trạng cạn kiệt tài nguyên, dịch vụ Thanh toán bị sập (Downtime). Điện thoại reo lúc 2 giờ sáng. Nam và Hoa bật máy tính nhưng không biết bắt đầu từ đâu. Họ tốn 15 phút để tìm bảng điều khiển (Dashboard) trên Grafana, tốn thêm 20 phút để cãi nhau xem ai có quyền xóa Pod lỗi, và không ghi chép lại nguyên nhân. Sáng hôm sau, sếp yêu cầu báo cáo nhưng không ai nắm rõ toàn cảnh sự cố.

Mentor Minh lắc đầu và kết luận:
> *"Một hệ thống tự động hóa hoàn hảo sẽ trở thành thảm họa tài chính nếu không có **Rào chắn chi phí (Cost Guard)** chặn ở cấp độ Không gian tên (Namespace). Hơn nữa, việc ứng cứu sự cố không thể phụ thuộc vào trí nhớ cá nhân. Các em phải xây dựng văn hóa vận hành bằng các cuộc diễn tập phá hoại có chủ đích (Chaos Testing) và tuân thủ chặt chẽ **Cẩm nang ứng cứu (Runbook)**."*

---

## Phần 2: Rào Chắn Chi Phí (Cost Guard) Cấp Cụm Với K8s

Để giải quyết vấn đề hóa đơn đám mây tăng vọt do bất cẩn, Kỹ sư nền tảng (Platform Engineer) phải thiết lập kỷ luật thép ngay tại cụm máy chủ. Lập trình viên có quyền tự do phát hành ứng dụng, nhưng sự tự do đó nằm trong khuôn khổ hữu hạn.

### 1. LimitRange (Giới Hạn Từng Nhóm Vùng Chứa)
Nhiều lập trình viên thường quên khai báo tài nguyên (Requests/Limits) trong tệp triển khai (Deployment). K8s mặc định cho phép Pod tiêu thụ tài nguyên vô hạn.
**`LimitRange`** là cơ chế tự động ép buộc các giới hạn tối thiểu/tối đa, hoặc tự động "điền hộ" cấu hình tài nguyên mặc định cho từng Pod trong Không gian tên nếu lập trình viên bỏ sót.

*Tệp cấu hình LimitRange (`limit-range.yaml`):*
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: xshop-default-limits
  namespace: xshop-dev # Áp dụng riêng cho môi trường Dev
spec:
  limits:
  - default: # Giá trị Limit mặc định nếu không khai báo
      memory: 512Mi
      cpu: 500m
    defaultRequest: # Giá trị Request mặc định nếu không khai báo
      memory: 256Mi
      cpu: 250m
    max: # Cấm hoàn toàn việc tạo Pod có giới hạn lớn hơn mức này
      memory: 1Gi
      cpu: 1000m
    type: Container
```

### 2. ResourceQuota (Hạn Mức Tổng Của Không Gian Tên)
Nếu `LimitRange` giới hạn từng Pod, thì **`ResourceQuota`** giới hạn tổng lượng tài nguyên mà toàn bộ Không gian tên (Đại diện cho một Đội dự án) được phép tiêu thụ.
Điều này ngăn chặn triệt để tình trạng một đội dự án "chiếm đoạt" tài nguyên của các đội khác hoặc kích hoạt mua máy chủ bừa bãi.

*Tệp cấu hình ResourceQuota (`resource-quota.yaml`):*
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: xshop-team-quota
  namespace: xshop-dev
spec:
  hard:
    requests.cpu: "4"       # Đội dự án chỉ được yêu cầu tối đa 4 lõi CPU tổng cộng
    requests.memory: 8Gi    # Tối đa 8GB RAM tổng cộng
    pods: "20"              # Không được phép chạy quá 20 Pods cùng lúc
    services.loadbalancers: "2" # Chỉ được tạo tối đa 2 bộ cân bằng tải vật lý (Đắt tiền)
```
*Lưu ý:* Khi cấu hình này được áp dụng, nếu đội lập trình cố tình triển khai Pod thứ 21, API Server của K8s sẽ lập tức từ chối yêu cầu (Reject) kèm mã lỗi vượt hạn mức (Quota Exceeded).

---

## Phần 3: Giám Sát Bất Thường Trên Đám Mây (AWS Cost Anomaly Detection)

Hạn mức K8s chỉ bảo vệ được cụm máy chủ. Đối với các tài nguyên ngoài cụm (như Phí lưu lượng mạng băng thông ngoài, Phí lưu trữ S3, Dịch vụ máy học), ta phải sử dụng trí tuệ nhân tạo của AWS.

**AWS Cost Anomaly Detection (Phát hiện chi phí bất thường)** sử dụng học máy (Machine Learning) để phân tích mô hình tiêu dùng lịch sử.
*   **Ví dụ**: Tiền mạng (Data Transfer Egress) của dự án X-Shop trung bình mỗi ngày là $5 USD. Nếu một ngày có cấu hình sai làm lượng dữ liệu truyền ra ngoài tăng vọt khiến chi phí nhảy lên $50 USD/ngày.
*   **Hành động**: Hệ thống AWS sẽ phát hiện sự bất thường này ngay trong ngày và bắn thông báo qua Slack/Email cho đội ngũ tài chính hoặc kỹ sư trưởng thay vì phải đợi đến cuối tháng mới nhìn thấy hóa đơn nghìn đô.

---

## Phần 4: Văn Hóa Ứng Cứu Sự Cố Bằng Cẩm Nang (Runbook) & Chaos Testing

Khi sự cố (Incident) xảy ra, SRE (Kỹ sư vận hành độ tin cậy) không được phép hành động theo bản năng. Mọi thao tác phải tuân theo một kịch bản đã được lập trình sẵn gọi là **Runbook** (Cẩm nang vận hành).

### 1. Diễn Tập Phá Hoại (Chaos Engineering)
Để kiểm chứng Runbook có thực sự hoạt động, dự án áp dụng **Chaos Testing**. SRE sẽ chủ động tiêm lỗi (Fault Injection) vào hệ thống trong giờ hành chính (Ví dụ: Chủ động xóa ngẫu nhiên 3 Pod Database, hoặc ngắt kết nối mạng nội bộ giữa các khu vực). Mục đích là để xem hệ thống Tự phục hồi (Self-healing) có tốt không và đội ngũ trực chiến xử lý có đúng quy trình không.

### 2. Kịch Bản Ứng Cứu 6 Bước Chuẩn SRE (Incident Response Playbook)
Một Runbook chuẩn khi đối mặt với sự cố hệ thống sập phải tuân thủ 6 bước khắt khe:

1.  **Phát hiện (Detect)**: Nhận cảnh báo (Alert) từ hệ thống giám sát (Ví dụ: Fast Burn Rate Alert báo tỷ lệ lỗi $> 14.4\text{x}$).
2.  **Đánh giá mức độ (Triage)**: Ai là Trưởng nhóm ứng cứu (Incident Commander)? Mức độ nghiêm trọng là gì (SEV-1: Hệ thống sập toàn phần, SEV-2: Tính năng nhỏ bị lỗi)?
3.  **Khoanh vùng cô lập (Contain)**: Cầm máu ngay lập tức. (Ví dụ: Trả trọng số bộ định tuyến về phiên bản cũ, cấu hình Nhóm bảo mật AWS (Security Group) chặn IP tấn công). Tạm thời chưa tìm nguyên nhân gốc (Root Cause) ở bước này.
4.  **Loại trừ (Eradicate)**: Tìm hiểu vì sao bị lỗi và tung ra bản vá mã nguồn chính thức (Hotfix) thông qua luồng CI/CD (Tuyệt đối không sửa tay trên máy chủ).
5.  **Khôi phục (Recover)**: Đưa lưu lượng người dùng quay trở lại hệ thống một cách từ từ (Sử dụng Canary), kiểm tra lại các chỉ số đo lường (Metrics).
6.  **Hậu kiểm (Post-mortem)**: Sau khi sự cố kết thúc, toàn đội ngồi lại viết báo cáo không đổ lỗi (Blameless). Câu hỏi trọng tâm: *"Tại sao sự cố xảy ra? Làm sao để tự động hóa việc chặn lỗi này trong tương lai bằng mã nguồn (IaC/Policy)?"*

---

## Phần 5: Tổng Kết Hệ Sinh Thái "Platform Engineering" Đóng Gói (End-to-End)

Chặng đường từ Tuần 8 đến Tuần 10 đã trang bị cho các kỹ sư một Nền tảng lập trình viên nội bộ (IDP - Internal Developer Platform) hoàn chỉnh:

*   **Lớp Hạ Tầng Dưới Cùng (W8)**: Mã hóa toàn bộ kiến trúc mạng, máy chủ ảo, cơ sở dữ liệu trên AWS bằng Terraform, với quản lý trạng thái từ xa (Remote State) an toàn.
*   **Lớp Điều Phối (W8)**: Đóng gói ứng dụng vào Kubernetes, tận dụng khả năng tự phục hồi của Pods và điều hướng mạng tự động (Services).
*   **Lớp Phân Phối (W9)**: Từ bỏ việc đẩy cấu hình thủ công. Áp dụng chuẩn GitOps (ArgoCD) kết hợp với triển khai chim hoàng yến (Argo Rollouts).
*   **Lớp Giám Sát (W9)**: Theo dõi sức khỏe hệ thống bằng bộ tiêu chuẩn OpenTelemetry, phản ứng thông minh dựa trên Tốc độ đốt ngân sách lỗi (Burn Rate).
*   **Lớp Bảo Vệ & Quản Trị (W10)**: Xiết chặt phân quyền bằng RBAC, IRSA. Chặn mọi sai sót bằng chính sách tự động (Admission Policy), khóa chặt mã bí mật bằng ESO, và giới hạn chi phí tuyệt đối bằng ResourceQuota.

Đây chính là chuẩn mực của một nền tảng Đám mây cấp doanh nghiệp (Enterprise-grade Cloud Platform). Các đội phát triển giờ đây có thể tự phục vụ (Self-service) việc ra mắt tính năng mới chỉ trong vài phút, tự động, an toàn và hoàn toàn có khả năng đo lường.
