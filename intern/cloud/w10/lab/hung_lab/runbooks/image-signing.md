# Hướng Dẫn Vận Hành: Quét Lỗ Hổng Bảo Mật Và Ký Xác Thực Image (Image Signing & Verification)

Tài liệu này hướng dẫn cách kiểm tra, vận hành và xử lý sự cố đối với hệ thống tự động quét lỗi bảo mật, ký xác thực chữ ký số lên các container image và kiểm soát triển khai phần mềm an toàn trong cụm Kubernetes.

---

## 1. Cách Hoạt Động Của Hệ Thống

Để ngăn chặn các phần mềm độc hại, chứa lỗi bảo mật nghiêm trọng hoặc không rõ nguồn gốc chạy trong hệ thống, chuỗi cung ứng phần mềm được siết chặt qua 3 chốt chặn bảo mật:
1. **CI Pipeline (Quét lỗ hổng tự động):** Mỗi khi lập trình viên cập nhật mã nguồn lên GitHub, hệ thống CI (GitHub Actions) sẽ tự động chạy công cụ **Trivy** để quét các lỗi bảo mật bên trong sản phẩm. Nếu phát hiện lỗi mức độ **HIGH** hoặc **CRITICAL**, quy trình sẽ lập tức bị hủy bỏ (báo đỏ) để ngăn chặn phát hành image lỗi.
2. **Cosign (Ký số):** Nếu bước quét bảo mật vượt qua thành công, hệ thống sử dụng khóa bảo mật riêng tư (`cosign.key`) để ký số và gắn chữ ký xác thực lên Image, sau đó đẩy cả Image và chữ ký lên kho chứa GitHub Container Registry (GHCR).
3. **Admission Controller (Kiểm tra khi triển khai):** Trên cụm Kubernetes, công cụ **Sigstore Policy Controller** được cài đặt để giám sát. Khi có yêu cầu chạy ứng dụng mới, nó sử dụng khóa công khai (`cosign.pub`) để kiểm tra chữ ký của Image đó. Nếu Image chưa được ký hoặc ký bằng khóa lạ, Kubernetes sẽ lập tức **chặn đứng** không cho chạy.

---

## 2. Hướng Dẫn Tạo Khóa Ký Ảnh (Cosign Keypair)

Khi cần tạo cặp khóa ký ảnh mới (chạy trên máy cục bộ của bạn):

1. Đảm bảo công cụ `cosign` đã được cài đặt.
2. Chạy câu lệnh tạo khóa (thiết lập mật khẩu bảo vệ khóa ở biến đầu tiên):
   ```bash
   COSIGN_PASSWORD="MatKhauBaoVeKhoaCuaBan" cosign generate-key-pair
   ```
3. Sau khi chạy, hệ thống sẽ tạo ra 2 file trong thư mục hiện hành:
   * `cosign.key`: Khóa riêng tư dùng để ký ảnh (Cần giữ bí mật tuyệt đối, **KHÔNG ĐƯỢC** đưa lên Git).
   * `cosign.pub`: Khóa công khai dùng để xác thực ảnh (An toàn khi đưa lên Git).

---

## 3. Thiết Lập Hệ Thống GitHub Tự Động Ký Ảnh

Để GitHub Actions tự động ký ảnh sau khi build thành công:
1. Truy cập vào kho mã nguồn (Repository) của bạn trên GitHub.
2. Chọn **Settings** (Cài đặt) -> **Secrets and variables** -> **Actions** -> Chọn nút **New repository secret**.
3. Tạo 2 Secret sau:
   * **Secret 1:**
     * Name: `COSIGN_PRIVATE_KEY`
     * Value: (Mở file `cosign.key` trên máy bạn, copy toàn bộ nội dung và dán vào đây).
   * **Secret 2:**
     * Name: `COSIGN_PASSWORD`
     * Value: Mật khẩu bảo vệ khóa bạn vừa thiết lập ở phần trên (ví dụ: `MatKhauBaoVeKhoaCuaBan`).

---

## 4. Cách Kiểm Tra Và Nghiệm Thu Kết Quả

Hệ thống được nghiệm thu dựa trên 3 tình huống kiểm chứng thực tế sau:

### Tình huống 1: Deploy Image chưa được ký (Bị chặn)
Triển khai một image chưa được ký thuộc phạm vi quản lý vào namespace có bật kiểm soát chữ ký (`dev`):
```bash
kubectl run test-unsigned --image=ghcr.io/vuong-bach/w10-api:0.0.1 -n dev
```
* **Kết quả kỳ vọng:** Lệnh thất bại ngay lập tức và hiển thị thông báo lỗi:
  > *Error from server (BadRequest): admission webhook "policy.sigstore.dev" denied the request ... no signatures found* 🛑

### Tình huống 2: Deploy Image đã ký (Được chấp nhận)
Triển khai image đã được build và ký số tự động từ hệ thống GitHub Actions của bạn:
```bash
kubectl run test-signed --image=ghcr.io/YOUR_GITHUB_USER/w10-api:1.0.0 -n dev
```
* **Kết quả kỳ vọng:** Pod được tạo thành công:
  > *pod/test-signed created*  ✅

### Tình huống 3: Triển khai các ứng dụng thông thường không thuộc diện kiểm soát (Được chấp nhận)
Triển khai các ứng dụng tiêu chuẩn như `nginx` vào namespace:
```bash
kubectl run test-allowed --image=nginx:latest -n dev
```
* **Kết quả kỳ vọng:** Pod được tạo thành công nhờ cấu hình `no-match-policy: allow` của bộ lọc.

---

## 5. Hướng Dẫn Xử Lý Sự Cố Thường Gặp

### Lỗi 1: Pod triển khai bị lỗi "validation failed: no signatures found"
* **Nguyên nhân:** Image bạn đang deploy chưa được ký bằng khóa riêng tư tương ứng, hoặc chữ ký chưa được đẩy lên Registry (GHCR).
* **Cách xử lý:**
  1. Kiểm tra xem quy trình GitHub Actions có chạy thành công bước `Sign image` không.
  2. Ký thủ công lại image nếu cần thiết bằng lệnh trên máy cá nhân:
     ```bash
     COSIGN_PASSWORD="MatKhauBaoVeKhoaCuaBan" cosign sign --key cosign.key ghcr.io/YOUR_GITHUB_USER/w10-api:1.0.0
     ```

### Lỗi 2: Tránh chèn ép ứng dụng hiện tại khi mới kích hoạt
* **Lưu ý quan trọng:** Khi bạn bật tính năng kiểm tra chữ ký cho một namespace bằng nhãn (label) `policy.sigstore.dev/include=true`, toàn bộ các pod trong đó sẽ bị kiểm tra khi khởi động lại.
* **Quy tắc an toàn:** Chỉ gắn nhãn (label) kích hoạt bộ lọc sau khi bạn đã chắc chắn image ứng dụng của bạn đã được ký và đẩy chữ ký thành công lên registry. Nếu gắn nhãn trước khi ký, ứng dụng hiện tại khi cập nhật hoặc tự hồi sinh sẽ bị chặn đứng lập tức.
