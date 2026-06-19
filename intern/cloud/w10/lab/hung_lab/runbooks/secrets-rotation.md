# Hướng Dẫn Vận Hành: Tự Động Xoay Vòng Mật Khẩu (Secrets Rotation)

Tài liệu này hướng dẫn cách kiểm tra, vận hành và xử lý sự cố liên quan đến hệ thống tự động đồng bộ và cập nhật mật khẩu cơ sở dữ liệu (Database Password) từ dịch vụ đám mây AWS Secrets Manager về ứng dụng chạy trong cụm Kubernetes mà không cần phải khởi động lại hệ thống.

---

## 1. Cách Hoạt Động Của Hệ Thống

Hệ thống được thiết lập tự động hóa hoàn toàn qua 4 bước:
1. **AWS Secrets Manager (Nguồn):** Nơi quản lý mật khẩu gốc an toàn. Khi mật khẩu thay đổi ở đây, hệ thống sẽ bắt đầu chu trình cập nhật.
2. **External Secrets Operator - ESO (Bộ đồng bộ):** Cứ mỗi 60 giây, bộ đồng bộ này sẽ kiểm tra xem mật khẩu trên AWS có thay đổi hay không. Nếu có, nó tự động tải về và cập nhật vào Kubernetes.
3. **Volume Mount (Bộ truyền dẫn):** Mật khẩu trong Kubernetes được ánh xạ thành một file vật lý nằm tại thư mục `/secrets/password` bên trong container chạy ứng dụng API. Kubernetes tự động cập nhật nội dung file này khi mật khẩu thay đổi.
4. **API Application (Ứng dụng):** Mã nguồn ứng dụng API được lập trình để đọc trực tiếp nội dung file `/secrets/password` mỗi khi có yêu cầu truy vấn, nhờ đó áp dụng mật khẩu mới ngay lập tức mà không cần khởi động lại.

---

## 2. Quy Trình Thay Đổi Mật Khẩu Trên AWS

Khi cần đổi mật khẩu cơ sở dữ liệu (ví dụ định kỳ hoặc do yêu cầu bảo mật):

1. Mở cửa sổ dòng lệnh (Terminal).
2. Chạy câu lệnh sau để cập nhật mật khẩu mới lên dịch vụ AWS (thay đổi giá trị mật khẩu mới ở phần cuối câu lệnh nếu cần):

   ```bash
   aws secretsmanager update-secret \
     --secret-id prod/db/password \
     --secret-string "MatKhauMoiCuaBan123" \
     --region ap-southeast-1
   ```

3. Màn hình sẽ hiển thị thông tin xác nhận dạng chữ JSON cho biết mật khẩu đã được cập nhật thành công trên dịch vụ AWS đám mây.

---

## 3. Cách Kiểm Tra Và Nghiệm Thu Kết Quả

Sau khi đổi mật khẩu trên AWS, hãy thực hiện các bước sau để đảm bảo mật khẩu mới đã tự động đi vào hệ thống:

### Bước 3.1: Kiểm tra mật khẩu trong Kubernetes
Chạy câu lệnh sau để giải mã mật khẩu đang lưu trong Kubernetes:

```bash
kubectl get secret db-secret -n demo -o jsonpath='{.data.password}' | base64 -d; echo ""
```
* **Kết quả kỳ vọng:** Trong vòng tối đa 60 giây kể từ khi đổi trên AWS, mật khẩu hiển thị trên màn hình phải là mật khẩu mới (`MatKhauMoiCuaBan123`).

### Bước 3.2: Kiểm tra khả năng nhận biết của Ứng dụng (API)
Chạy câu lệnh sau để kiểm tra xem ứng dụng API đang chạy trong Pod đã nhận diện mật khẩu mới chưa:

```bash
kubectl exec -it deployment/api -n demo -c api -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8080/db-secret').read().decode())"
```
* **Kết quả kỳ vọng:** Dòng chữ JSON trả về hiển thị `"password_preview"` chứa những chữ cái đầu của mật khẩu mới (ví dụ: `"MatKh..."`).
* **Lưu ý quan trọng:** Hãy chạy lệnh sau để kiểm tra thời gian hoạt động (AGE) của Pod:
  ```bash
  kubectl get pods -n demo -l app=api
  ```
  Thời gian cột `AGE` phải liên tục (không bị reset về `1s` hay `2s`), chứng minh Pod không hề bị khởi động lại mà vẫn nhận được mật khẩu mới.

---

## 4. Hướng Dẫn Xử Lý Sự Cố Thường Gặp

### Lỗi 1: Mật khẩu trên AWS đã đổi nhưng trong Kubernetes vẫn là mật khẩu cũ
* **Nguyên nhân:** Bộ đồng bộ ESO chưa đến chu kỳ quét (mặc định 60 giây) hoặc gặp lỗi kết nối AWS.
* **Cách xử lý:** 
  1. Kiểm tra trạng thái của bộ đồng bộ bằng lệnh:
     ```bash
     kubectl get externalsecret db-creds -n demo
     ```
     Nếu cột `STATUS` hiển thị khác `SecretSynced` hoặc `READY` hiển thị `False`, hệ thống đang gặp lỗi kết nối.
  2. Xem chi tiết lỗi bằng lệnh:
     ```bash
     kubectl describe externalsecret db-creds -n demo
     ```
     Đọc phần `Events` ở cuối để xem lý do cụ thể (ví dụ: sai tài khoản AWS, hết hạn kết nối).
  3. Ép hệ thống đồng bộ ngay lập tức mà không cần chờ:
     ```bash
     kubectl annotate externalsecret db-creds -n demo force-sync=$(date +%s) --overwrite
     ```

### Lỗi 2: Lỗi "AccessDeniedException" (Không có quyền truy cập)
* **Nguyên nhân:** Tài khoản AWS lưu trong cụm Kubernetes (`aws-credentials`) không có quyền đọc mật khẩu từ AWS Secrets Manager.
* **Cách xử lý:**
  1. Đảm bảo thông tin Access Key ID và Secret Access Key của tài khoản có quyền đọc Secrets Manager.
  2. Cập nhật lại tài khoản đúng vào cụm bằng lệnh:
     ```bash
     kubectl delete secret aws-credentials -n demo --ignore-not-found
     kubectl create secret generic aws-credentials -n demo \
       --from-literal=access-key-id=YOUR_ACCESS_KEY_ID \
       --from-literal=secret-access-key=YOUR_SECRET_ACCESS_KEY
     ```
