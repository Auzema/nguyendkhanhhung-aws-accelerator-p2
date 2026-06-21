# Tài Liệu Chuyên Sâu: Bảo Mật Chuỗi Cung Ứng (Supply Chain Security) & Quản Lý Vòng Đời Mã Bí Mật

---

## Phần 1: Câu Chuyện Thực Tế — Hiểm Họa Từ Mã Nguồn Độc Hại & Mã Bí Mật Bị Đánh Cắp

Hệ thống phân quyền đã được siết chặt ở Tuần 10 Phần 1, Nam và Hoa tự tin rằng kiến trúc dự án X-Shop đã an toàn. Nhưng Mentor Minh tiếp tục chỉ ra một lỗ hổng chí mạng ở giai đoạn trước khi mã nguồn được triển khai (Giai đoạn Tích hợp liên tục - CI):

> *"Hàng rào bảo vệ vững chắc nhất cũng vô dụng nếu kẻ thù đã luồn sẵn vào bên trong từ nhà máy sản xuất. Nếu hacker chèn một thư viện độc hại chứa lỗ hổng tống tiền (Ransomware) vào tập lệnh của ứng dụng (Image), hoặc một lập trình viên vô tình tải lên GitHub một đoạn mã chứa mật khẩu cơ sở dữ liệu, K8s (Kubernetes) sẽ ngây thơ tin tưởng và kéo chúng về chạy. Đó là lỗ hổng Chuỗi cung ứng phần mềm (Software Supply Chain)."*

Hai thảm họa thực tế đã từng xảy ra:
1.  **Lộ lọt mã bí mật (Secret Leakage)**: Mật khẩu cơ sở dữ liệu bị lộ trên GitHub công khai. Hacker dùng mật khẩu này kết nối vào hệ thống và xóa sạch dữ liệu. Kỹ sư vội vàng đổi mật khẩu trên bảng điều khiển cơ sở dữ liệu, nhưng quên không khởi động lại 30 Pods ứng dụng K8s, dẫn đến ứng dụng cũ gọi mật khẩu cũ và sập toàn tập.
2.  **Đánh tráo hình ảnh (Image Spoofing)**: Tin tặc xâm nhập vào kho lưu trữ (Container Registry), ghi đè hình ảnh `backend:v1.2` bằng một hình ảnh chứa mã đào tiền ảo. K8s tự động kéo hình ảnh này về và máy chủ bị vắt kiệt CPU.

Mục tiêu mới: Phải tự động hóa việc xoay vòng mã bí mật (Secrets Rotation) và thiết lập hệ thống **Bảo mật DevSecOps (Tích hợp bảo mật vào quy trình Phát triển và Vận hành)** để chặn đứng mọi mã nguồn chứa lỗ hổng hoặc không có chữ ký xác thực.

---

## Phần 2: Quản Lý & Xoay Vòng Mã Bí Mật Với External Secrets Operator (ESO)

Bản thân K8s Secret mặc định chỉ mã hóa base64 (rất dễ dịch ngược). Do đó, Nguồn sự thật duy nhất (Single Source of Truth) để lưu mật khẩu phải là các hệ thống chuyên dụng cấp doanh nghiệp như AWS Secrets Manager hoặc HashiCorp Vault.

**External Secrets Operator (Bộ thao tác mã bí mật ngoại vi - ESO)** là một công cụ giúp tự động đồng bộ mật khẩu từ AWS Secrets Manager về cụm K8s dưới dạng K8s Secret thông thường.

### 1. Luồng Hoạt Động Của ESO
1.  SRE tạo mật khẩu an toàn trên AWS Secrets Manager.
2.  SRE tạo tài nguyên `ExternalSecret` trên K8s.
3.  ESO đọc `ExternalSecret`, sử dụng danh tính IRSA (Quyền truy cập đám mây cho tài khoản K8s) gọi API lên AWS để kéo mật khẩu về.
4.  ESO tự động sinh ra một K8s Secret vật lý để các Pod sử dụng.

### 2. File Khai Báo External Secret Mẫu
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: backend-db-secret
  namespace: xshop-app
spec:
  refreshInterval: "1m" # Cứ 1 phút, ESO sẽ kiểm tra và tự động đồng bộ nếu AWS có mật khẩu mới
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-credentials-secret # Tên của K8s Secret sẽ được ESO sinh ra
    creationPolicy: Owner
  data:
  - secretKey: DB_PASSWORD # Khóa biến môi trường bên trong K8s Secret
    remoteRef:
      key: xshop/backend/database # Tên Secret lưu trên AWS Secrets Manager
      property: password # Thuộc tính lấy từ chuỗi JSON trên AWS
```

### 3. Tự Động Xoay Vòng Không Gây Gián Đoạn (Rotation < 60s No-Restart)
Khi AWS tự động xoay vòng mật khẩu (Rotation), ESO sẽ nhận thấy sự thay đổi sau tối đa 1 phút (`refreshInterval: 1m`) và cập nhật K8s Secret.
Tuy nhiên, Pod K8s **không tự động nhận biến môi trường mới** nếu không được khởi động lại. Để giải quyết, hệ thống cài đặt thêm công cụ **Reloader**. Reloader tự động theo dõi K8s Secret; nếu mật khẩu thay đổi, nó sẽ thực hiện Cập nhật cuốn chiếu (Rolling Update) khởi động lại tuần tự các Pod một cách mượt mà để nhận cấu hình mới mà không làm rớt mạng của khách hàng.

---

## Phần 3: Quét Lỗ Hổng & Mã Bí Mật (Shift-Left Security)

Triết lý "Dịch trái" (Shift-Left) trong DevSecOps nghĩa là kéo các khâu kiểm tra bảo mật về càng sớm càng tốt trong vòng đời phát triển phần mềm (Ngay tại bước CI/CD thay vì đợi đến lúc chạy trên máy chủ).

### 1. Secret Scanning Trong CI
Để tránh sự cố lộ mật khẩu trên GitHub, ta thiết lập kịch bản hành động GitHub (GitHub Actions) chạy công cụ quét tĩnh (Ví dụ: `trufflehog` hoặc `gitleaks`). Bất kỳ yêu cầu hợp nhất mã (Pull Request) nào chứa chuỗi ký tự giống API Key, Token hay Password đều bị đánh dấu "Thất bại" (Fail) ngay lập tức.

### 2. Quét Hình Ảnh Bằng Trivy
Hình ảnh vùng chứa (Container Image) thường chứa rất nhiều thư viện phụ thuộc (Dependencies). Công cụ **Trivy** được thêm vào luồng CI để quét toàn bộ thư viện và hệ điều hành bên trong hình ảnh xem có chứa các Lỗ hổng bảo mật chung (CVE - Common Vulnerabilities and Exposures) hay không.

Quy tắc áp dụng (Policy): **Fail-on HIGH/CRITICAL**.
Nếu Trivy phát hiện bất kỳ CVE nào ở mức CAO (High) hoặc NGHIÊM TRỌNG (Critical), luồng CI sẽ thất bại và không cho đẩy hình ảnh đó lên kho lưu trữ.

```yaml
# Đoạn mã GitHub Actions quét Trivy
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'techx/xshop-backend:${{ github.sha }}'
    format: 'table'
    exit-code: '1' # Trả về lỗi nếu phát hiện vi phạm
    severity: 'CRITICAL,HIGH' # Chỉ bắt lỗi mức Cao và Nghiêm trọng
```

### 3. Ngoại Lệ Bằng ADR (Exception Policy)
Trong một số trường hợp, một thư viện hệ thống bị báo lỗi mức HIGH, nhưng hệ thống hiện tại chưa có bản vá, hoặc thư viện đó không bị gọi tới trong logic thực tế.
Lập trình viên không thể vì một lỗi này mà dừng triển khai toàn bộ dự án. Khi đó, nhóm phát triển phải viết một Báo cáo quyết định kiến trúc (ADR - Architecture Decision Record) yêu cầu một Ngoại lệ (Exception) có thời hạn (ví dụ: Bỏ qua lỗi CVE-2024-1234 trong vòng 30 ngày) để luồng CI tiếp tục chạy, và cam kết nâng cấp khi có bản vá chính thức.

---

## Phần 4: Đảm Bảo Tính Toàn Vẹn Bằng Chữ Ký Số (Cosign/Sigstore)

Ngay cả khi hình ảnh đã quét sạch CVE, làm sao K8s biết được hình ảnh đó thực sự do hệ thống CI nội bộ của TechX tạo ra, chứ không phải do hacker giả mạo tải lên kho lưu trữ?

Khái niệm Mức độ Chuỗi cung ứng (SLSA - Supply chain Levels for Software Artifacts) yêu cầu mọi phần mềm phải được Ký điện tử (Sign) để xác nhận nguồn gốc không bị giả mạo. Ta sử dụng công cụ **Cosign** (thuộc dự án Sigstore).

### 1. Cơ Chế Ký Không Khóa (Keyless Signing với OIDC)
Quản lý cặp Khóa công khai / Khóa riêng tư (Public/Private Keys) rất phức tạp và rủi ro nếu bị lộ khóa riêng tư. Cosign hỗ trợ ký **Keyless** bằng cách kết hợp với danh tính của hệ thống CI (GitHub Actions thông qua giao thức OIDC). Hình ảnh sẽ được gắn nhãn chứng minh "Hình ảnh này được tạo ra một cách hợp lệ từ GitHub Repository của dự án X-Shop".

*Lệnh thực thi tự động trong CI:*
```bash
# Đăng nhập bằng OIDC Token của GitHub
cosign sign --yes techx/xshop-backend:v1.2.0
```

### 2. Xác Thực Hình Ảnh Trước Khi Kéo (Admission Webhook Verify Signature)
Để đóng hoàn toàn lỗ hổng, cụm K8s được cài đặt trình điều khiển tự động xác minh chữ ký (Cosign Admission Webhook hoặc Kyverno/Gatekeeper).

Khi có một lệnh yêu cầu chạy Pod mang hình ảnh `techx/xshop-backend:v1.2.0`, trình điều khiển K8s sẽ:
1.  Chặn yêu cầu lại.
2.  Kiểm tra trên kho lưu trữ xem hình ảnh này có chứa chữ ký số hợp lệ từ hệ thống CI của TechX hay không.
3.  **Từ chối (Reject)**: Nếu không có chữ ký (do hacker tải lén lên) hoặc chữ ký không khớp.
4.  **Chấp nhận (Allow)**: Nếu chữ ký hợp lệ, Pod mới được phép tiến hành khởi tạo.

Mô hình bảo mật đa tầng từ khâu viết mã (CI Scanning), đóng gói (Image Signing), quản lý vòng đời mật khẩu (ESO/Rotation) đến khâu vận hành K8s (Admission Verification) giúp dự án X-Shop vô hiệu hóa hầu hết các cuộc tấn công cung ứng hiện đại.
