# Hành Trình Terraform Phần 1: Phá Bỏ Cơn Ác Mộng "Click Tay"

Chào mừng bạn đến với chuyên đề đầu tiên trong chuỗi ôn luyện DevOps. Thay vì đọc những tài liệu lý thuyết khô khan, chúng ta sẽ cùng đồng hành với **Nam** — một SRE Intern vừa gia nhập dự án X-Shop của TechX — vượt qua thử thách đầu đời từ **Mentor Minh**.

Qua câu chuyện của Nam, bạn sẽ nắm trọn vẹn kiến thức về **IaC (Infrastructure as Code)**, cú pháp **HCL**, và luồng vận hành cốt lõi của **Terraform** để sẵn sàng cho buổi vấn đáp sắp tới.

---

## 📖 Chương 1: Cơn Ác Mộng Click-Tay Trên AWS Console

Vào một buổi sáng thứ Hai đẹp trời, Mentor Minh giao cho Nam nhiệm vụ đầu tiên:
> *"Nam ơi, em lên AWS tạo cho anh một hạ tầng cơ bản để chạy ứng dụng nhé. Gồm có: 1 VPC, 1 Subnet, 1 EC2 Instance đóng vai trò Web Server và 1 S3 Bucket để lưu ảnh sản phẩm."*

Nam hí hửng đồng ý. Cậu đăng nhập vào trang quản trị AWS Console, bắt đầu cuộc hành trình "click chuột":
1. Tìm dịch vụ VPC $\rightarrow$ Click Create VPC $\rightarrow$ Điền IP CIDR.
2. Tìm dịch vụ EC2 $\rightarrow$ Chọn AMI, chọn size `t3.micro` $\rightarrow$ Tạo Key Pair $\rightarrow$ Cấu hình Security Group mở cổng 80 và 22.
3. Tìm dịch vụ S3 $\rightarrow$ Tạo bucket với tên `xshop-product-images-dev` $\rightarrow$ Tắt Block Public Access để hiển thị ảnh.

Sau gần 2 tiếng đồng hồ vừa click vừa tra cứu, Nam tự hào báo cáo hoàn thành. Mọi thứ chạy trơn tru.

### Bước Ngoặt Xuất Hiện
Mentor Minh mỉm cười gật đầu: 
> *"Tốt lắm Nam. Bây giờ, khách hàng muốn có thêm một môi trường **Staging** để QC test, và một môi trường **Production** để chạy thật. Em tạo thêm 2 môi trường giống hệt Dev giúp anh nhé."*

Nam bắt đầu toát mồ hôi. Cậu lại tiếp tục hành trình click chuột. Nhưng lần này:
* Ở môi trường **Staging**: Cậu lỡ tay gõ nhầm IP CIDR của Subnet, dẫn đến việc ứng dụng không thể kết nối tới Database. Cậu tốn thêm 1 tiếng để rà soát lỗi.
* Ở môi trường **Production**: Cậu quên không mở cổng 80 trên Security Group, khiến khách hàng không truy cập được vào Web Server.
* Tồi tệ hơn, khi sếp hỏi: *"Hạ tầng hiện tại của chúng ta đang cấu hình cụ thể gồm những gì?"*, Nam không cách nào chỉ ra được ngoài việc chụp lại hàng chục màn hình AWS Console.

**Vấn đề cốt lõi ở đây là gì?**
* **Thiếu nhất quán (Inconsistency)**: Click tay rất dễ sai sót. Càng nhiều môi trường, tỉ lệ lỗi càng cao.
* **Không có tài liệu lịch sử (No History/Version Control)**: Không ai biết ai đã sửa đổi cái gì, vào lúc nào trên Console.
* **Tốc độ chậm & Khó tái sử dụng (Low Reusability)**: Mỗi lần tạo mới hoặc dọn dẹp hạ tầng là một lần cực hình.

---

## 🛠️ Chương 2: Sứ Mệnh Giải Cứu Của Terraform & Ngôn Ngữ HCL

Thấy Nam loay hoay, Mentor Minh vỗ vai cậu và đưa ra một chiếc chìa khóa vàng: **Terraform**.
> *"Trong DevOps, tụi anh không click tay. Tụi anh dùng **Infrastructure as Code (IaC)**. Hạ tầng phải được định nghĩa bằng mã nguồn. Em hãy dùng Terraform và viết lại toàn bộ cấu trúc đó thành file code."*

Nam bắt đầu tìm hiểu. Terraform sử dụng ngôn ngữ **HCL (HashiCorp Configuration Language)**. Cú pháp của nó cực kỳ dễ đọc, giống như khai báo thông tin thay vì lập trình logic phức tạp.

Dưới đây là file `main.tf` đầu tiên mà Nam viết để định nghĩa hạ tầng AWS của mình:

```hcl
# 1. Khai báo Provider: Giống như việc chọn "nhà phân phối" hạ tầng. 
# Ở đây ta báo cho Terraform biết ta muốn làm việc với AWS ở khu vực Singapore (ap-southeast-1).
provider "aws" {
  region = "ap-southeast-1"
}

# 2. Khai báo Biến (Variables): Giúp code linh hoạt, dễ tái sử dụng cho nhiều môi trường.
variable "environment" {
  type        = string
  description = "Tên môi trường triển khai"
  default     = "dev"
}

# 3. Tạo tài nguyên VPC: Căn nhà mạng độc lập của chúng ta.
resource "aws_vpc" "xshop_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "xshop-vpc-${var.environment}"
  }
}

# 4. Tạo Subnet bên trong VPC
resource "aws_subnet" "xshop_subnet" {
  vpc_id            = aws_vpc.xshop_vpc.id # Tham chiếu động ID của VPC vừa tạo ở trên
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-southeast-1a"

  tags = {
    Name = "xshop-subnet-${var.environment}"
  }
}

# 5. Tạo S3 Bucket lưu ảnh sản phẩm
resource "aws_s3_bucket" "product_images" {
  bucket = "xshop-product-images-unique-${var.environment}" # Tên bucket phải là duy nhất trên toàn cầu

  tags = {
    Name = "xshop-product-images-${var.environment}"
  }
}

# 6. Đầu ra (Outputs): Giống như việc in kết quả ra màn hình sau khi tạo xong.
output "vpc_id" {
  value       = aws_vpc.xshop_vpc.id
  description = "ID của VPC được tạo ra"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.product_images.arn
  description = "Định danh ARN của S3 Bucket"
}
```

### 💡 Lời khuyên của Mentor Minh giúp Nam hiểu cú pháp HCL:
* **Block Type**: Là loại khai báo (ví dụ: `provider`, `variable`, `resource`, `output`).
* **Resource Type** (ví dụ: `aws_vpc`): Do nhà cung cấp (AWS) định nghĩa, bắt đầu bằng tên của provider.
* **Resource Name** (ví dụ: `xshop_vpc`): Là tên do ta tự đặt trong code để các tài nguyên khác tham chiếu đến nhau (như cách Subnet lấy `aws_vpc.xshop_vpc.id`).
* **Arguments**: Các cấu hình nằm trong dấu ngoặc nhọn `{}` (như `cidr_block = "10.0.0.0/16"`).

---

## 🔄 Chương 3: Vòng Đời Hạ Tầng — 4 Lệnh Chạy Huyền Thoại

Sau khi viết xong file `main.tf`, Nam mở terminal lên. Cậu cần đưa đống code này lên AWS thật. Để làm việc đó, cậu phải trải qua quy trình 4 bước tiêu chuẩn của Terraform.

```
       [Viết code .tf]
              │
              ▼
      1. terraform init     (Tải plugin/provider)
              │
              ▼
      2. terraform plan     (Xem trước bản vẽ hạ tầng)
              │
              ▼
      3. terraform apply    (Triển khai lên AWS)
              │
              ▼
     [Hạ tầng hoạt động]
              │
              ▼
     4. terraform destroy   (Dọn dẹp tài nguyên)
```

### Bước 1: `terraform init` (Khởi tạo dự án)
Khi Nam gõ lệnh này, Terraform đọc file code và phát hiện ta đang dùng provider `"aws"`. Nó lập tức lên mạng tải plugin tương thích của AWS về thư mục ẩn `.terraform/` trên máy Nam. 
> *Ý nghĩa*: Giống như việc bạn mua một chiếc máy in mới, bạn phải cài driver của hãng đó vào máy tính thì mới in được.

### Bước 2: `terraform plan` (Lập kế hoạch thiết kế)
Nam gõ lệnh này để kiểm tra xem chuyện gì sẽ xảy ra. Terraform sẽ phân tích code, so sánh với thực tế trên AWS và đưa ra một danh sách dự kiến:
* Tài nguyên nào sẽ được tạo mới (ký hiệu bằng dấu `+`).
* Tài nguyên nào sẽ bị chỉnh sửa (ký hiệu bằng dấu `~`).
* Tài nguyên nào sẽ bị xóa bỏ (ký hiệu bằng dấu `-`).
> *Ý nghĩa*: Đây là bước kiểm tra an toàn cực kỳ quan trọng. Nó giúp ta biết trước hậu quả của dòng code mình viết mà chưa làm thay đổi gì trên AWS.

### Bước 3: `terraform apply` (Tiến hành xây dựng)
Sau khi thấy bản kế hoạch ở bước `plan` hoàn hảo, Nam gõ lệnh này và điền `yes` để xác nhận. Terraform trực tiếp gọi API của AWS để tạo ra VPC, Subnet và S3 Bucket y hệt như code mô tả. Lúc này, file trạng thái bí ẩn mang tên `terraform.tfstate` được sinh ra để lưu lại thông tin chi tiết của những tài nguyên vừa tạo.

### Bước 4: `terraform destroy` (Dọn dẹp hạ tầng)
Khi dự án X-Shop kết thúc thử nghiệm, Nam không muốn tiếp tục bị AWS tính tiền. Thay vì lên Console đi tìm từng dịch vụ để xóa, cậu chỉ cần gõ duy nhất một lệnh `terraform destroy`. Toàn bộ hạ tầng định nghĩa trong file code lập tức bị xóa sạch sẽ theo đúng thứ tự an toàn (xóa Subnet trước rồi mới xóa VPC).

---

## ⚠️ Chương 4: Thử Thách Đụng Độ Thực Tế — Hiện Tượng "Drift" (Trôi Lệch Cấu Hình)

Một tuần sau, khi dự án đang chạy ổn định. Bỗng nhiên ứng dụng X-Shop không thể kết nối tới S3 Bucket. 
Hóa ra, một developer khác trong team vì muốn sửa lỗi gấp trong đêm đã tự ý lên AWS Console đổi tên cấu hình phân quyền của Bucket này mà không sửa trong code Terraform của Nam.

Nam chạy lệnh `terraform plan` để kiểm tra. Ngay lập tức, Terraform hiển thị thông báo phát hiện sự khác biệt giữa **Thực tế trên AWS Cloud** và **File trạng thái local (`terraform.tfstate`)**. Hiện tượng này được gọi là **Drift (Trôi lệch hạ tầng)**.

### Cách Terraform giải quyết:
Terraform hoạt động theo nguyên lý **Khai báo (Declarative)**. Nghĩa là code viết thế nào, hạ tầng thực tế phải đúng như thế. 
Khi chạy `terraform apply`, Terraform sẽ tự động cấu hình lại S3 Bucket trên AWS để đưa nó quay trở về đúng trạng thái ban đầu được mô tả trong code của Nam, đè bẹp thay đổi tự ý click tay của dev kia.

Nam thở phào nhẹ nhõm. Từ nay, không ai có thể âm thầm phá hỏng hạ tầng nữa!

---

## 🎯 Chương 5: Bộ Câu Hỏi Vượt Ải Phỏng Vấn Với Mentor Minh

Để giúp bạn vượt qua buổi vấn đáp DevOps sắp tới, dưới đây là những câu hỏi thực tế mà Mentor Minh thường hỏi học viên ở chuyên đề này, đi kèm gợi ý trả lời chuẩn chỉnh.

### 🟢 Mức độ: DỄ (Hiểu khái niệm cốt lõi)

#### **Câu 1: Infrastructure as Code (IaC) mang lại lợi ích gì lớn nhất so với việc quản trị hạ tầng truyền thống (click tay)?**
*   **Gợi ý trả lời**: IaC mang lại 3 lợi ích cốt lõi:
    1.  **Nhất quan (Consistency)**: Loại bỏ hoàn toàn lỗi cấu hình sai lệch do con người khi nhân bản môi trường (Dev, Staging, Prod).
    2.  **Tự động hóa & Tốc độ**: Triển khai hoặc dọn dẹp toàn bộ hệ thống lớn chỉ bằng một dòng lệnh trong vài phút thay vì hàng giờ click tay.
    3.  **Quản lý phiên bản (Version Control)**: Hạ tầng được lưu trữ dưới dạng code giúp lưu lại lịch sử thay đổi qua Git, dễ dàng review code (Pull Request) trước khi hạ tầng được tạo ra.

#### **Câu 2: Phân biệt sự khác nhau giữa `terraform plan` và `terraform apply`?**
*   **Gợi ý trả lời**: 
    *   `terraform plan` là lệnh chạy thử (dry run). Nó chỉ đọc code, so sánh với trạng thái thực tế và đưa ra dự báo xem sẽ có những tài nguyên nào được tạo, sửa hoặc xóa mà **chưa hề làm thay đổi** hạ tầng thật.
    *   `terraform apply` mới là lệnh thực thi thật. Nó sẽ áp dụng các thay đổi đó lên AWS và cập nhật thông tin vào file `terraform.tfstate`.

---

### 🟡 Mức độ: TRUNG BÌNH (Hiểu cơ chế vận hành)

#### **Câu 3: Imperative (Mệnh lệnh) và Declarative (Khai báo) khác nhau như thế nào? Terraform thuộc loại nào và tại sao nó lại tối ưu hơn?**
*   **Gợi ý trả lời**:
    *   **Imperative (Mệnh lệnh - ví dụ: AWS CLI, Ansible)**: Bạn phải chỉ ra từng bước để đạt được mục tiêu (Ví dụ: *"Tạo VPC $\rightarrow$ Đợi 10s $\rightarrow$ Tạo Subnet $\rightarrow$ Tạo EC2"*). Nếu hệ thống đã có sẵn VPC, lệnh có thể bị lỗi.
    *   **Declarative (Khai báo - ví dụ: Terraform, K8s)**: Bạn chỉ cần mô tả trạng thái cuối cùng bạn mong muốn (Ví dụ: *"Tôi muốn có 1 VPC và 1 EC2"*). Terraform tự động tính toán xem hệ thống đang thiếu gì để bù đắp hoặc thừa gì để xóa bỏ để đạt đúng trạng thái đó.
    *   **Tối ưu hơn**: Lối tư duy khai báo giúp viết code ngắn gọn hơn, không cần xử lý các logic rẽ nhánh phức tạp hay kiểm tra xem tài nguyên đã tồn tại chưa, giúp code an toàn và dễ bảo trì hơn.

#### **Câu 4: Chuyện gì xảy ra nếu ai đó tự ý xóa một S3 Bucket bằng tay trên AWS Console? Khi ta chạy `terraform plan` tiếp theo, Terraform sẽ phản ứng thế nào?**
*   **Gợi ý trả lời**: Khi chạy `terraform plan`, Terraform sẽ quét hạ tầng thực tế trên AWS trước tiên. Nó phát hiện S3 Bucket được mô tả trong code không còn tồn tại ngoài đời thực (mặc dù vẫn có tên trong file `terraform.tfstate`). Terraform sẽ cập nhật lại bộ nhớ của nó và đưa ra kế hoạch (plan) với ký hiệu `+ create` để tạo lại S3 Bucket đó nhằm đưa hạ tầng thực tế khớp đúng với mong muốn trong code.

---

### 🔴 Mức độ: KHÓ (Vận dụng thực tế dự án)

#### **Câu 5: Trong dự án của em, nếu em vô tình chạy `terraform destroy` nhầm trên môi trường Production, làm thế nào để ngăn chặn thảm họa này xảy ra?**
*   **Gợi ý trả lời**: Để ngăn chặn thảm họa xóa nhầm trên Production, chúng ta áp dụng các biện pháp sau:
    1.  **Sử dụng Lifecycle Rule `prevent_destroy`**: Khai báo trực tiếp trong block tài nguyên quan trọng (như RDS Database, S3 Bucket lưu data). Nếu ai đó chạy lệnh destroy, Terraform sẽ từ chối thực thi ngay lập tức.
        ```hcl
        lifecycle {
          prevent_destroy = true
        }
        ```
    2.  **Phân quyền IAM chặt chẽ**: Tài khoản CI/CD chạy Terraform trên Production phải được giới hạn quyền. Chỉ cấp quyền xóa khi có sự phê duyệt đặc biệt.
    3.  **Bật Versioning và MFA Delete**: Trên AWS S3, luôn bật Versioning và tính năng yêu cầu mã xác thực MFA trước khi xóa vĩnh viễn dữ liệu.
    4.  **Tách biệt State file**: Không dùng chung state file giữa Dev và Prod. Đảm bảo thư mục code Prod nằm riêng biệt và yêu cầu cấu hình xác thực nghiêm ngặt khi chuyển ngữ cảnh.

#### **Câu 6: Hãy kể lại một tình huống lỗi "Drift" (Trôi lệch cấu hình) thực tế em từng gặp trong dự án và cách em xử lý nó bằng Terraform.**
*   **Gợi ý trả lời**:
    *   *Tình huống*: Trong dự án X-Shop, team phát triển phát hiện ứng dụng không gửi được log về Elasticsearch. Một bạn dev đã vào trực tiếp Security Group của EC2 trên AWS Console mở tạm cổng `9200` ra ngoài internet (`0.0.0.0/0`) để debug nhanh rồi quên không đóng lại. Việc này tạo ra lỗ hổng bảo mật nghiêm trọng.
    *   *Phát hiện*: Khi chạy pipeline CI/CD hàng ngày chứa bước quét hạ tầng `terraform plan`, hệ thống lập tức báo đỏ vì phát hiện Security Group thực tế có thêm rule mở cổng 9200 không hề được khai báo trong Git.
    *   *Cách xử lý*: Thay vì sửa tay trên Console, em đã chạy trực tiếp `terraform apply`. Terraform nhận thấy sự trôi lệch này và tự động xóa bỏ (revoke) rule mở cổng 9200 trái phép trên AWS, đưa Security Group về đúng trạng thái an toàn ban đầu được phê duyệt trong code Git. Đồng thời, em viết một ADR (Architecture Decision Record) để hướng dẫn team nếu muốn mở cổng phải tạo Pull Request sửa code Terraform và được duyệt qua quy trình CI/CD.
