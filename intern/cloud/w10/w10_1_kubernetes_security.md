# Tài Liệu Chuyên Sâu: Bảo Mật K8s (Kubernetes) - Phân Quyền RBAC, IRSA & Áp Đặt Chính Sách Admission

---

## Phần 1: Câu Chuyện Thực Tế — Lỗ Hổng Leo Thang Đặc Quyền & Chính Sách "Không Tin Tưởng Ai"

Nam và Hoa sau khi hoàn thành hệ thống phân phối ứng dụng tự động, họ đối mặt với một thử thách mới từ Mentor Minh liên quan đến an ninh bảo mật:
> *"Hệ thống chạy mượt mà chưa chắc đã an toàn. Hiện tại, tài khoản của các nhà phát triển (Developers) và tài khoản hệ thống của CI/CD đều dùng chung quyền `cluster-admin` tối cao. Nếu một lập trình viên vô tình làm lộ tệp cấu hình kubeconfig, hoặc triển khai một Pod cấu hình sai bảo mật, toàn bộ cụm máy chủ của TechX sẽ bị sập."*

Mối đe dọa này lập tức trở thành hiện thực trong một buổi Thử nghiệm xâm nhập (Penetration Testing):
1.  **Sự cố chạy quyền root**: Một lập trình viên cấu hình tệp triển khai chạy vùng chứa (Container) dưới quyền root (`runAsUser: 0`) và gắn trực tiếp thư mục hệ thống của máy chủ vật lý (`hostPath: /`) vào bên trong Pod để ghi nhật ký nhanh.
2.  **Lộ khóa đám mây**: Lập trình viên đó cũng truyền thẳng khóa bảo mật AWS (AWS Access Keys) vào biến môi trường của Pod để tải hình ảnh từ kho lưu trữ.
3.  **Hacker chiếm cụm máy chủ**: Chuyên gia bảo mật đóng vai tin tặc khai thác một lỗi thực thi mã độc từ xa (RCE - Remote Code Execution) trên ứng dụng Web. Do container chạy quyền root và có quyền truy cập thư mục gốc của máy chủ vật lý, tin tặc lập tức thoát khỏi container (Container Breakout), lấy cắp khóa AWS, sửa đổi tệp mật khẩu `/etc/shadow` của máy chủ, từ đó chiếm quyền điều khiển hoàn toàn máy chủ Nút (Node) và toàn bộ tài nguyên đám mây.

Mentor Minh yêu cầu thiết lập lớp phòng thủ đa tầng:
> *"Chúng ta phải thiết lập nguyên tắc **Quyền hạn tối thiểu (Least Privilege)** bằng **RBAC**. Kế tiếp, loại bỏ khóa AWS cứng bằng **IRSA**. Cuối cùng, áp dụng cơ chế chặn vi phạm ngay từ vòng gửi xe bằng **Admission Controllers (Bộ kiểm soát xác nhận đầu vào)**. Dù lập trình viên có viết tệp khai báo xin quyền admin cho Pod, hệ thống cũng phải tự động từ chối."*

---

## Phần 2: Phân Quyền Tối Thiểu Với K8s RBAC & Tích Hợp Đám Mây IRSA

### 1. Phân Quyền Nội Bộ Bằng RBAC (Role-Based Access Control)
RBAC là cơ chế quản lý phân quyền trong K8s dựa trên vai trò của người dùng hoặc tài khoản hệ thống (ServiceAccount). Nguyên tắc cốt lõi: Không cung cấp quyền `cluster-admin` cho bất kỳ ai ngoại trừ Kỹ sư vận hành hệ thống (SRE).

*   **`Role` / `ClusterRole`**: Định nghĩa NHỮNG GÌ được phép làm (Ví dụ: Quyền `get`, `list`, `create` trên đối tượng `pods`). `Role` bị giới hạn trong một Không gian tên (Namespace), còn `ClusterRole` áp dụng cho toàn bộ cụm.
*   **`RoleBinding` / `ClusterRoleBinding`**: Liên kết AI (User/ServiceAccount) với cái `Role` đó.

*Mã cấu hình giới hạn quyền cho Developer (`developer-role.yaml`):*
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: xshop-app
  name: developer-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch"] # Nghiêm cấm quyền "delete"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-role-binding
  namespace: xshop-app
subjects:
- kind: ServiceAccount
  name: developer-sa
roleRef:
  kind: Role
  name: developer-role
  apiGroup: rbac.authorization.k8s.io
```

Kỹ sư có thể kiểm tra nhanh đặc quyền của một tài khoản thông qua lệnh kiểm tra giả lập:
```bash
# Giả lập quyền của ServiceAccount developer-sa để xem có được phép xóa Pod không
kubectl auth can-i delete pods -n xshop-app --as system:serviceaccount:xshop-app:developer-sa
# Kết quả: no
```

### 2. Định Danh Dám Mây Với IRSA (IAM Roles for Service Accounts)
Làm sao để một Pod trong cụm EKS (Amazon Elastic Kubernetes Service) có thể truy cập Dịch vụ lưu trữ S3 (Simple Storage Service) mà không cần nhúng Khóa truy cập AWS (AWS Access Keys) vào mã nguồn?

Giải pháp là **IRSA**. IRSA kết nối hệ thống phân quyền của K8s với hệ thống phân quyền của AWS (IAM).
1.  K8s ServiceAccount sẽ được cấp một chứng chỉ danh tính liên kết (OIDC Token).
2.  AWS IAM tin tưởng chứng chỉ OIDC này và cho phép ServiceAccount nhận tạm thời một Vai trò AWS (IAM Role).
3.  Pod sử dụng ServiceAccount đó sẽ có quyền truy cập S3 một cách vô hình và an toàn.

*Cấu hình nhãn (Annotation) cho ServiceAccount nhận quyền AWS:*
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-sa
  namespace: xshop-app
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/XShopS3AccessRole
```

---

## Phần 3: Thiết Lập Chính Sách Chặn Với OPA/Gatekeeper (Rego)

Khi các kỹ sư viết tệp YAML, họ vẫn có thể khai báo chạy dưới quyền root. Ta sử dụng **OPA (Open Policy Agent - Công cụ đánh giá chính sách đa năng)** cùng **Gatekeeper** hoạt động như một Webhook (Điểm chặn HTTP nội bộ) để từ chối các tệp không tuân thủ chính sách bảo mật trước khi chúng được ghi vào hệ thống.

### Phân biệt ConstraintTemplate vs Constraint
*   **`ConstraintTemplate`**: Định nghĩa hàm logic kiểm tra (sử dụng ngôn ngữ lập trình khai báo **Rego**). Nó mang tính trừu tượng tổng quát (Ví dụ: Hàm kiểm tra xem container có chạy quyền root hay không).
*   **`Constraint`**: Thực thi hàm đó vào thực tế cụ thể. Nó định nghĩa Không gian tên nào bị áp dụng luật này.

*Tệp khai báo `ConstraintTemplate` chặn quyền root:*
```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sblockrootcontainers
spec:
  crd:
    spec:
      names:
        kind: K8sBlockRootContainers
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sblockrootcontainers
        # Nếu hàm is_root trả về True, sinh ra thông báo lỗi và Chặn
        violation[{"msg": msg}] {
          container := input.review.object.spec.template.spec.containers[_]
          is_root(container)
          msg := sprintf("Container '%v' đang chạy quyền root. Vui lòng tắt quyền.", [container.name])
        }
        is_root(c) { c.securityContext.runAsNonRoot == false }
        is_root(c) { c.securityContext.runAsUser == 0 }
```

---

## Phần 4: Bảo Mật Bản Địa Với ValidatingAdmissionPolicy (CEL)

Bắt đầu từ phiên bản **Kubernetes 1.30+**, K8s cung cấp cơ chế bảo mật tích hợp sâu gọi là **`ValidatingAdmissionPolicy`** để thay thế cho sự cồng kềnh của OPA/Gatekeeper.

*   **Hiệu năng vượt trội**: Gatekeeper yêu cầu máy chủ K8s phải gửi luồng tin mạng ra ngoài để kiểm tra, gây độ trễ. ValidatingAdmissionPolicy chạy trực tiếp (In-process) trong máy chủ K8s, cho tốc độ tức thì.
*   **Ngôn ngữ đơn giản**: Sử dụng cú pháp **CEL (Common Expression Language - Ngôn ngữ biểu thức chung)** thay thế cho ngôn ngữ Rego phức tạp.

*Tệp chính sách CEL chặn gắn ổ đĩa hệ thống (hostPath) và yêu cầu hệ thống tệp chỉ đọc (readOnlyRootFilesystem):*
```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: pss-restricted-policy
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: ["apps"]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["deployments"]
  validations:
    - expression: |
        !has(self.spec.template.spec.volumes) || 
        self.spec.template.spec.volumes.all(v, !has(v.hostPath))
      message: "Vi phạm Pod Security Standards: Nghiêm cấm mount hostPath."
    - expression: |
        has(self.spec.template.spec.containers[0].securityContext) &&
        self.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem == true
      message: "Vi phạm: Container phải thiết lập readOnlyRootFilesystem: true để chống lại mã độc ghi đè."
```

---

## Phần 5: Tiêu Chuẩn Bảo Mật Vùng Chứa (Pod Security Standards - PSS)

Cộng đồng Kubernetes định nghĩa 3 cấp độ Tiêu chuẩn bảo mật (PSS):
1.  **Privileged (Đặc quyền)**: Không áp dụng bất kỳ hạn chế nào. Chỉ dùng cho các vùng chứa hệ thống (như Hệ thống mạng CNI).
2.  **Baseline (Cơ bản)**: Cấm các leo thang đặc quyền (Privilege Escalation) đã biết.
3.  **Restricted (Hạn chế tối đa)**: Mức độ bảo vệ cao nhất. Bắt buộc tệp triển khai phải khai báo rõ `runAsNonRoot: true`, thả rơi các quyền gốc Linux (`drop: ["ALL"]`) và thiết lập hệ thống tệp chỉ đọc (`readOnlyRootFilesystem: true`).

Kỹ sư vận hành (SRE) thiết lập tự động chặn các nhóm vùng chứa không đạt chuẩn Restricted bằng cách gắn nhãn vào Không gian tên:
```bash
kubectl label namespace xshop-app pod-security.kubernetes.io/enforce=restricted
```

---

## Phần 6: Chế Độ Vận Hành Chính Sách — Audit (Kiểm Kê) vs Enforce (Chặn Đứng)

Khi triển khai các bộ luật bảo mật cực đoan vào một hệ thống đang chạy ổn định trên thực tế, việc kích hoạt "Chặn Đứng" ngay lập tức sẽ làm chết toàn bộ các dịch vụ chưa kịp cập nhật chuẩn mới.

1.  **Chế độ Kiểm tra (Audit Mode)**:
    *   Hệ thống VẪN cho phép tạo Pod vi phạm để dịch vụ không bị gián đoạn.
    *   Các lỗi vi phạm được ghi vào tệp Nhật ký kiểm toán (Audit Logs) và đẩy lên CloudWatch.
    *   Giúp SRE rà soát xem có bao nhiêu hệ thống đang vi phạm để lập báo cáo yêu cầu cập nhật mã nguồn (Grace period).
2.  **Chế độ Chặn đứng (Enforce Mode)**:
    *   Trả về thẳng lỗi `403 Forbidden` trên màn hình của lập trình viên hoặc làm thất bại đường ống CI/CD.
    *   Kích hoạt chế độ này khi $100\%$ hệ thống đã cập nhật xong mã nguồn để chốt chặn vĩnh viễn rủi ro bảo mật.
