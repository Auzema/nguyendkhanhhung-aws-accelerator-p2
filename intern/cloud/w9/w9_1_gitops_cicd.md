# Tài Liệu Chuyên Sâu: GitOps & CI/CD - Xây Dựng Luồng Phân Phối Liên Tục Lấy Git Làm Trung Tâm

---

## Phần 1: Câu Chuyện Thực Tế — Xung Đột Trạng Thái Và Vấn Đề "Trôi Lệch Cấu Hình"

Sau khi hoàn tất khóa huấn luyện W8 với Minikube, Nam và Hoa áp dụng Terraform và Kubernetes vào hệ thống thực tế của X-Shop. Tuy nhiên, một cơn ác mộng mới trong quá trình vận hành (Operations) lại xuất hiện:

1.  **Vấn đề đè chồng cấu hình (Configuration Overwrite)**: Nam vừa cập nhật cấu hình RAM tối đa cho dịch vụ Backend bằng lệnh `kubectl apply -f backend-deployment.yaml` từ máy cá nhân. 10 phút sau, Hoa cần sửa đổi cổng giao tiếp, nhưng cô sử dụng file `backend-deployment.yaml` phiên bản cũ trên máy tính của cô (chưa kéo thay đổi của Nam về). Khi lệnh apply của Hoa chạy xong, giới hạn RAM của Nam lập tức bị đè mất.
2.  **Vấn đề "Trôi lệch im lặng" (Silent Drift)**: Nửa đêm, hệ thống Database bị thắt cổ chai, một kỹ sư cao cấp dùng đặc quyền để chạy trực tiếp lệnh `kubectl edit deployment/backend` trên cluster nhằm tăng kết nối tối đa. Hệ thống cứu vãn thành công, nhưng thay đổi này không bao giờ được đưa vào mã nguồn trên kho lưu trữ. Sáng hôm sau, kịch bản tự động hóa chạy lại bằng cấu hình trên kho lưu trữ, ghi đè toàn bộ thay đổi lúc nửa đêm khiến hệ thống sập lần thứ hai.
3.  **Vấn đề khôi phục hoảng loạn (Rollback Panic)**: Đợt phát hành sáng thứ hai gặp lỗi nghiêm trọng. Hoa cuống cuồng chạy lệnh `kubectl rollout undo deployment/backend` để quay về phiên bản trước. Tuy nhiên, mã nguồn trên kho lưu trữ vẫn đang là phiên bản lỗi. Trạng thái thực tế và mã nguồn bị tách rời hoàn toàn.

Mentor Minh phân tích nguyên nhân cốt lõi:
> *"Các em đang quản trị cụm Kubernetes bằng phương thức 'Đẩy' (Push) - đẩy mã từ bất kỳ máy nào lên cụm. Tư duy vận hành hiện đại đòi hỏi chúng ta phải áp dụng **GitOps**. Trong mô hình này, **Git phải là Nguồn Sự Thật Duy Nhất (Single Source of Truth)**. Toàn bộ hạ tầng phải được tự động 'Kéo' (Pull) từ Git về cụm. Không ai được quyền can thiệp trực tiếp vào cụm."*

---

## Phần 2: Kiểm Soát Đầu Vào Với CI/CD Pipeline (GitHub Actions)

Nguyên lý đầu tiên của GitOps là ngăn chặn mã lỗi được hòa trộn (Merge) vào nhánh chính. Kịch bản kiểm định (CI - Continuous Integration) đóng vai trò như một người gác cổng.

### 1. Luồng Plan-on-PR (Lập Bản Vẽ Khi Tạo Yêu Cầu Gộp Code)
Khi lập trình viên tạo PR (Pull Request - yêu cầu hợp nhất code), kịch bản tự động trên GitHub Actions sẽ không thay đổi hệ thống ngay, mà chỉ chạy lệnh `terraform plan` để phác thảo các thay đổi dự kiến. Kết quả này được tự động bình luận (Comment) ngược lại vào PR, giúp người duyệt (Reviewer) thấy chính xác những gì sắp xảy ra (thêm máy chủ nào, xóa tài nguyên nào) mà không cần cài đặt Terraform trên máy.

### 2. Luồng Apply-on-Merge (Thực Thi Khi Code Được Gộp)
Chỉ sau khi nhóm trưởng phê duyệt và tiến hành Merge PR vào nhánh chính (`main`), kịch bản CD (Continuous Delivery) mới được kích hoạt để chạy lệnh `terraform apply -auto-approve` áp dụng thay đổi vào môi trường thực tế.

### 3. Cấu Hình An Toàn Tối Đa Với OIDC (OpenID Connect)
Thay vì lưu trữ các khóa truy cập dài hạn (Access Keys) của AWS vào GitHub Secrets (tiềm ẩn rủi ro lộ lọt), dự án áp dụng chuẩn **OIDC (OpenID Connect - Giao thức xác thực dựa trên token)**. GitHub sẽ được cấp một chứng chỉ tạm thời (Short-lived Token) có thời hạn 1 giờ để giao tiếp với AWS, triệt tiêu hoàn toàn rủi ro lộ khóa.

```yaml
# Cấu hình GitHub Actions CI/CD Mẫu
name: Tự Động Hóa Hạ Tầng
on:
  pull_request:
    branches: [ main ]
  push:
    branches: [ main ]
permissions:
  id-token: write # Cấp quyền cho OIDC
  contents: read
  pull-requests: write # Quyền ghi bình luận kết quả Plan
jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Định danh AWS bằng OIDC
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
          aws-region: ap-southeast-1
      - name: Lập bản vẽ (Plan)
        if: github.event_name == 'pull_request'
        run: terraform plan -no-color -out=tfplan
      - name: Thực thi (Apply)
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve
```

---

## Phần 3: Trận Chiến GitOps Tools — ArgoCD vs FluxCD

Khi nhắc đến việc áp dụng mô hình GitOps (Kéo cấu hình tự động từ kho Git về Kubernetes), hai công cụ dẫn đầu thị trường là ArgoCD và FluxCD. 

| Tiêu Chí | **ArgoCD (Dự Án Chọn Lựa)** | **FluxCD** |
| :--- | :--- | :--- |
| **Giao diện trực quan (GUI)** | Sở hữu bảng điều khiển cực kỳ mạnh mẽ, hiển thị cây quan hệ của mọi tài nguyên K8s, trạng thái đồng bộ và sức khỏe hệ thống theo thời gian thực. | Lấy CLI (Giao diện dòng lệnh) làm trung tâm, không có GUI chính thức mạnh mẽ. Yêu cầu tích hợp công cụ bên ngoài. |
| **Phân quyền (RBAC)** | Hỗ trợ phân quyền người dùng (Role-Based Access Control) chi tiết (Ví dụ: Cho phép Dev xem log nhưng không được quyền xóa Pod). Rất tốt cho môi trường dùng chung cụm K8s. | Khó thiết lập phân quyền cho nhiều người dùng không chuyên lệnh. |
| **Triết lý Thiết kế** | Thiết kế dạng Ứng dụng (Application-centric), đóng gói nhóm tài nguyên thành một thẻ ứng dụng dễ nhìn. | Thiết kế dạng kiến trúc vi mô (Micro-controllers) rời rạc (Helm Controller, Kustomize Controller). |
| **Quản trị đa cụm** | Dễ dàng cài đặt một Hub trung tâm quản lý đẩy cấu hình tới hàng chục cụm từ xa. | Yêu cầu phải cài Flux riêng trên từng cụm và cấu hình phức tạp. |

Dự án X-Shop quyết định chọn **ArgoCD** làm công cụ cốt lõi cho môi trường Production nhờ giao diện trực quan và khả năng hỗ trợ sửa lỗi (Troubleshooting) nhanh chóng.

---

## Phần 4: Thiết Kế App-of-Apps & Sync Waves Trong ArgoCD

### 1. Mô Hình Ứng Dụng Chứa Ứng Dụng (App-of-Apps)
Quản trị thủ công hàng chục ứng dụng siêu nhỏ (Microservices) là điều không tưởng. ArgoCD sử dụng mẫu thiết kế App-of-Apps để giải quyết việc này. Ta định nghĩa duy nhất một "Ứng dụng Cha" có nhiệm vụ trỏ vào một thư mục trên Git chứa các file cấu hình của "Các ứng dụng Con". 
Khi cần thêm một Service mới, chỉ cần đẩy file `app.yaml` vào thư mục đó, Ứng dụng Cha sẽ tự động nhận diện và đẻ ra Ứng dụng Con trên cụm.

```text
├── argocd-apps/
│   ├── parent-app.yaml (Ứng dụng Cha trỏ vào thư mục children)
│   └── children/
│       ├── frontend-app.yaml
│       ├── backend-app.yaml
│       └── database-app.yaml
```

### 2. Kiểm Soát Thứ Tự Bằng Sync Waves
Trong thực tế, Backend không thể khởi động thành công nếu Database chưa ở trạng thái sẵn sàng. Nếu áp dụng cấu hình đồng loạt, Backend sẽ rơi vào trạng thái lỗi CrashLoopBackOff. ArgoCD cho phép điều phối thứ tự bằng **Sync Waves** (Làn sóng đồng bộ).

*Ví dụ cấu trúc luồng triển khai:*
1.  **Làn sóng -5**: Khởi tạo Namespace (Không gian tên) và cấu hình bảo mật.
2.  **Làn sóng 0**: Triển khai Database và đợi đến khi cơ sở dữ liệu xác nhận trạng thái sẵn sàng.
3.  **Làn sóng 5**: (Bắt đầu sau Làn sóng 0) Triển khai Backend và Frontend.

Khai báo thông qua nhãn (Annotation) trong tệp K8s:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: xshop-database
  annotations:
    argocd.argoproj.io/sync-wave: "0" # Ưu tiên khởi tạo trước
```

---

## Phần 5: Tại Tại Sao Tuyệt Đối Không Dùng Lệnh "kubectl rollout undo"?

Khi áp dụng ArgoCD, một trong những sai lầm nghiêm trọng nhất là thói quen khôi phục phiên bản bằng cách sử dụng các lệnh tương tác trực tiếp lên cụm K8s.

### Hậu Quả Của Việc Sửa Trực Tiếp (Drift)
1. Kỹ sư chạy lệnh `kubectl rollout undo deployment/backend` để quay về phiên bản cũ an toàn.
2. Hệ thống khôi phục, nhưng mã nguồn trên Git vẫn đang là phiên bản lỗi mới nhất.
3. ArgoCD với cơ chế `selfHeal: true` (tự động chữa lành) phát hiện trạng thái thực tế không khớp với Nguồn sự thật (Git). Nó lập tức chạy thuật toán đồng bộ, ghi đè lại phiên bản lỗi lên cụm. Trạng thái lỗi (Downtime) lại tiếp tục.

### Quy Trình Khôi Phục (Rollback) Chuẩn GitOps
1. Kỹ sư gõ lệnh `git revert <Mã_Commit_Lỗi>` trên kho lưu trữ cục bộ và Đẩy (Push) lên nhánh chính.
2. Nguồn sự thật trên Git đã được thay đổi về cấu hình an toàn cũ (có lịch sử rõ ràng).
3. Ngoặc điện báo (Webhook) báo cho ArgoCD biết có mã mới. ArgoCD sẽ lập tức kéo trạng thái an toàn về cụm.
4. Hệ thống được khôi phục, và trạng thái giữa Thực Tế và Git là nhất quán tuyệt đối.

**Triết lý sống còn**: Trong môi trường GitOps, cụm K8s chỉ dành để **"Đọc"** đối với con người. Mọi tác vụ phải được thực hiện thông qua **Mã nguồn (Git)**.
