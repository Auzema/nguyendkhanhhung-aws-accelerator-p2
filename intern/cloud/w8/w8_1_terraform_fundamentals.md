# Hành Trình Terraform Phần 1: Phá Bỏ Cơn Ác Mộng "Click Tay"

---

## 📖 Phần 1: Câu Chuyện Thực Tế — Cơn Ác Mộng Click-Tay & Trôi Lệch Cấu Hình

Vào một buổi sáng thứ Hai đẹp trời, Mentor Minh giao cho Nam — một SRE Intern mới gia nhập dự án X-Shop — nhiệm vụ đầu tiên:
> *"Nam ơi, em lên AWS tạo cho anh một hạ tầng cơ bản để chạy ứng dụng nhé. Gồm có: 1 VPC, 1 Subnet, 1 EC2 Instance đóng vai trò Web Server và 1 S3 Bucket để lưu ảnh sản phẩm."*

Nam đăng nhập vào trang quản trị AWS Console, bắt đầu cuộc hành trình "click chuột":
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
* Tồi tệ hơn, một developer khác trong team vì muốn sửa lỗi gấp trong đêm đã tự ý lên AWS Console đổi cấu hình của S3 Bucket mà không báo trước. Khi Nam chạy lại hệ thống, mọi thứ đổ vỡ mà không rõ nguyên nhân. Hiện tượng trôi lệch thực tế này được gọi là **Drift (Trôi lệch cấu hình)**.

Để giải quyết triệt để các vấn đề trên, Mentor Minh yêu cầu Nam chuyển dịch toàn bộ sang **Infrastructure as Code (IaC)** sử dụng **Terraform**. Kể từ đây, mọi hạ tầng của dự án sẽ được khai báo bằng code, lưu trữ lịch sử trên Git và kiểm soát nghiêm ngặt.

---

## 🛠️ Phần 2: Tài Liệu Kỹ Thuật Chuyên Sâu về Cú Pháp HCL

Dưới đây là phần phân tích kỹ thuật nghiêm túc và chi tiết về toàn bộ cú pháp HCL (HashiCorp Configuration Language) được áp dụng trong Terraform.

### 1. Cấu Trúc Khối Cấu Hình Hệ Thống (Terraform Block)
Khối `terraform {}` chứa các cài đặt cốt lõi của chính Terraform, bao gồm phiên bản Terraform yêu cầu và các provider cần thiết.

```hcl
terraform {
  required_version = ">= 1.5.0" # Ràng buộc phiên bản Terraform CLI

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Chỉ cho phép nâng cấp minor version (ví dụ: từ 5.0 lên 5.99, không lên 6.0)
    }
  }
}
```

### 2. Cấu Trúc Nhà Cung Cấp (Provider Block)
Đóng vai trò dịch mã HCL thành các lệnh gọi API của nhà cung cấp cloud tương ứng.

```hcl
provider "aws" {
  region = "ap-southeast-1"
  
  # Cấu hình Default Tags để tự động áp dụng tag cho tất cả tài nguyên được tạo bởi provider này
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "xshop"
      ManagedBy   = "Terraform"
    }
  }
}
```

### 3. Cấu Trúc Tài Nguyên (Resource Block)
Khai báo tài nguyên vật lý sẽ được khởi tạo trên cloud.

```
resource "aws_instance" "web_server" { ... }
   │          │             │
   │      Resource Type  Resource Name (Tên logic trong code)
Block Type
```

```hcl
resource "aws_instance" "web_server" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  # Tham chiếu động đến ID của một tài nguyên khác
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
}
```

### 4. Nguồn Dữ Liệu Đọc (Data Source Block)
Truy vấn thông tin từ các tài nguyên đã tồn tại sẵn trên cloud (được tạo thủ công hoặc từ một source khác) để sử dụng lại trong code mà không quản lý vòng đời của chúng.

```hcl
# Truy vấn AMI Amazon Linux 2 mới nhất từ AWS
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Sử dụng dữ liệu truy vấn được trong resource
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux_2.id # Sử dụng ID trả về từ data source
  instance_type = "t3.micro"
}
```

### 5. Khai Báo Biến Đầu Vào (Variables Block)
Giúp tham số hóa mã nguồn, tăng tính linh hoạt và bảo mật.

```hcl
variable "instance_count" {
  type        = number
  description = "Số lượng EC2 instances cần tạo"
  default     = 1
}

variable "db_password" {
  type        = string
  description = "Mật khẩu database"
  sensitive   = true # Ẩn giá trị biến trong log console khi plan/apply
}

variable "environment" {
  type        = string
  description = "Tên môi trường triển khai"
  
  # Block Validation: Ràng buộc giá trị hợp lệ của biến ngay khi compile
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Giá trị môi trường phải thuộc danh sách: dev, staging, prod."
  }
}
```

### 6. Giá Trị Địa Phương (Locals Block)
Đóng vai trò như các hằng số hoặc biến trung gian giúp gộp các biểu thức phức tạp lại để tái sử dụng nhiều lần trong file cấu hình, tránh lặp lại code.

```hcl
locals {
  name_prefix = "xshop-${var.environment}"
  common_tags = {
    Owner = "SRE-Team"
    Dept  = "Engineering"
  }
}

# Áp dụng local variable
resource "aws_s3_bucket" "log_bucket" {
  bucket = "${local.name_prefix}-logs"
  tags   = local.common_tags
}
```

### 7. Giá Trị Đầu Ra (Outputs Block)
Trả về các thông tin hữu ích sau khi triển khai thành công hạ tầng, thường dùng để hiển thị cho người vận hành hoặc truyền tham số cho các project Terraform khác.

```hcl
output "web_public_ip" {
  value       = aws_instance.web_server.public_ip
  description = "Địa chỉ IP công cộng của Web Server"
}

output "db_connection_string" {
  value       = "mongodb://${aws_instance.db.private_ip}:27017"
  sensitive   = true # Bảo mật chuỗi kết nối trong output đầu ra
}
```

---

## 🔁 Phần 3: Biến, Vòng Lặp & Câu Lệnh Điều Kiện trong HCL

Khi viết code chuyên nghiệp, ta cần tạo hạ tầng động dựa trên danh sách, cấu hình môi trường hoặc tạo tài nguyên có điều kiện.

### 1. Sử Dụng Tham Số Điều Kiện (Ternary Operator)
Cú pháp: `condition ? true_val : false_val`

```hcl
variable "enable_public_ip" {
  type    = bool
  default = true
}

resource "aws_instance" "app" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"
  
  # Nếu enable_public_ip = true thì gán IP public, ngược lại gán false
  associate_public_ip_address = var.enable_public_ip ? true : false
}
```

### 2. Vòng Lặp Với Tham Số `count`
Sử dụng khi muốn nhân bản nhiều tài nguyên giống hệt nhau hoặc tạo tài nguyên có điều kiện (bằng cách đặt `count = 0` hoặc `count = 1`).

```hcl
variable "create_bastion" {
  type    = bool
  default = true
}

# Nếu create_bastion = true, count = 1 (tạo 1 instance). Nếu false, count = 0 (không tạo instance nào)
resource "aws_instance" "bastion" {
  count         = var.create_bastion ? 1 : 0
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  tags = {
    # Sử dụng count.index (bắt đầu từ 0) để phân biệt tên từng instance
    Name = "bastion-host-${count.index}"
  }
}
```
*Nhược điểm của `count`*: Khi xóa một phần tử ở giữa danh sách, Terraform sẽ cập nhật lại toàn bộ index phía sau và có thể hủy/tạo lại ngoài mong muốn.

### 3. Vòng Lặp Với Tham Số `for_each`
Sử dụng khi muốn tạo các tài nguyên dựa trên một tập hợp (set) hoặc một bản đồ (map). Đây là giải pháp tối ưu hơn `count` vì mỗi tài nguyên được định danh bằng một khóa (key) chuỗi cụ thể chứ không phụ thuộc vào index số.

```hcl
variable "subnets_config" {
  type = map(object({
    cidr_block = string
    az         = string
  }))
  default = {
    subnet_a = { cidr_block = "10.0.1.0/24", az = "ap-southeast-1a" }
    subnet_b = { cidr_block = "10.0.2.0/24", az = "ap-southeast-1b" }
  }
}

resource "aws_subnet" "public" {
  for_each          = var.subnets_config # Lặp qua map subnets_config
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block # Lấy giá trị cidr_block
  availability_zone = each.value.az         # Lấy giá trị az

  tags = {
    Name = "subnet-${each.key}" # each.key là subnet_a hoặc subnet_b
  }
}
```

### 4. Vòng Lặp Trong Giá Trị (For Expressions & Splat Operator)
Dùng để biến đổi hoặc lọc các danh sách/map dữ liệu.

```hcl
variable "user_names" {
  type    = list(string)
  default = ["alice", "bob", "charlie"]
}

# Tạo danh sách các IAM User từ biến
resource "aws_iam_user" "users" {
  for_each = toset(var.user_names)
  name     = each.key
}

# Sử dụng For Expression để chuyển đổi danh sách tên viết hoa toàn bộ
output "uppercase_users" {
  value = [for name in var.user_names : upper(name)]
}

# Splat Operator (*): Lấy nhanh toàn bộ thuộc tính ARN từ danh sách IAM users
output "user_arns" {
  value = aws_iam_user.users[*].arn
}
```

---

## 🔒 Phần 4: Các Tham Số Siêu Cấu Hình (Meta-Arguments)

Meta-arguments là các tham số đặc biệt nằm trong block tài nguyên giúp kiểm soát cách Terraform xử lý và quản lý tài nguyên đó.

### 1. Ràng Buộc Phụ Thuộc Tương Tác (`depends_on`)
Mặc dù Terraform tự động phân tích đồ thị quan hệ để xác định thứ tự tạo tài nguyên, đôi khi có những mối quan hệ ngầm không thể hiện qua code. Ta dùng `depends_on` để ép buộc thứ tự.

```hcl
resource "aws_iam_role" "eks_role" {
  name = "eks-cluster-role"
  # ... code role ...
}

resource "aws_eks_cluster" "aws_eks" {
  name     = "xshop-eks"
  role_arn = aws_iam_role.eks_role.arn

  # Đảm bảo EKS Cluster chỉ được tạo SAU KHI IAM Role đã được tạo xong và hoạt động ổn định
  depends_on = [
    aws_iam_role.eks_role
  ]
}
```

### 2. Quản Lý Vòng Đời Tài Nguyên (`lifecycle` block)

#### **create_before_destroy (Tạo trước khi xóa)**
Mặc định, nếu thay đổi một tham số bắt buộc phải build lại tài nguyên, Terraform sẽ xóa tài nguyên cũ trước rồi mới tạo tài nguyên mới. Điều này gây ra downtime. Khai báo `create_before_destroy` giúp tạo tài nguyên mới chạy ổn định trước, sau đó mới dọn dẹp tài nguyên cũ.
```hcl
lifecycle {
  create_before_destroy = true
}
```

#### **prevent_destroy (Ngăn chặn hành vi xóa)**
Bảo vệ tài nguyên quan trọng khỏi các thao tác xóa vô ý (nhầm lệnh `terraform destroy`).
```hcl
lifecycle {
  prevent_destroy = true
}
```

#### **ignore_changes (Bỏ qua các cập nhật thay đổi ngoài code)**
Nếu có những tham số được cập nhật tự động ngoài cloud (ví dụ: AWS tự động sửa Auto Scaling group capacity, hoặc SRE đổi tag tay), ta báo cho Terraform bỏ qua những thuộc tính này khi đối chiếu drift.
```hcl
lifecycle {
  ignore_changes = [
    tags,
    associate_public_ip_address,
  ]
}
```

---

## ⚙️ Phần 5: Đi Sâu Luồng Làm Việc & Các Lệnh CLI Nâng Cao

Quy trình vận hành Terraform đòi hỏi sự chuẩn xác từ khâu định dạng, kiểm tra cú pháp cho tới triển khai.

### 1. Lệnh Khởi Tạo & Định Dạng Code
*   **`terraform init -upgrade`**: Cập nhật tất cả các provider plugins lên phiên bản mới nhất nằm trong khoảng ràng buộc cho phép.
*   **`terraform fmt`**: Tự động căn lề, định dạng lại toàn bộ file code `.tf` theo tiêu chuẩn HCL. Luôn luôn chạy lệnh này trước khi commit code.
*   **`terraform validate`**: Kiểm tra tính hợp lệ về cú pháp, biến khai báo, kiểu dữ liệu mà không cần gọi API AWS hay kiểm tra thực tế.

### 2. Lệnh Lập Kế Hoạch & Triển Khai
*   **`terraform plan -out=tfplan`**: Xuất bản vẽ hạ tầng ra một file nhị phân cụ thể tên là `tfplan`. Điều này đảm bảo rằng khi ta apply, Terraform sẽ chạy chính xác cấu hình đã được duyệt mà không sợ bị thay đổi giữa chừng.
*   **`terraform plan -var-file="production.tfvars"`**: Đọc các giá trị biến từ một file cấu hình biến dành riêng cho môi trường Production.
*   **`terraform apply "tfplan"`**: Triển khai trực tiếp từ bản vẽ đã xuất. Bước này sẽ bỏ qua câu hỏi xác nhận `yes` và đảm bảo an toàn tuyệt đối.
*   **`terraform apply -auto-approve`**: Bỏ qua bước hỏi xác nhận thủ công, thường dùng trong pipeline CI/CD.

### 3. Lệnh Quản Lý Trạng Thái (State Management CLI)
**Tuyệt đối không chỉnh sửa file `terraform.tfstate` bằng tay.** Muốn thay đổi state, ta phải tương tác qua bộ lệnh:
*   **`terraform state list`**: Liệt kê toàn bộ các tài nguyên hiện có trong file state.
*   **`terraform state show <resource_name>`**: Hiển thị thông tin chi tiết từng thuộc tính của tài nguyên cụ thể đang lưu trong state.
*   **`terraform state rm <resource_name>`**: Gỡ bỏ tài nguyên ra khỏi tầm quản lý của Terraform (tài nguyên ngoài cloud vẫn tồn tại nhưng Terraform sẽ không đối chiếu hay xóa nó nữa).
*   **`terraform state mv <old_name> <new_name>`**: Đổi tên logic của tài nguyên trong state khi ta thay đổi tên khai báo trong code `.tf` để tránh việc tài nguyên bị hủy và tạo lại.

---

## 🎯 Phần 6: Bộ Câu Hỏi Luyện Vấn Đáp Chuẩn Bị Với Mentor Minh

Dưới đây là hệ thống câu hỏi lý thuyết kết hợp tình huống dự án thực tế giúp bạn tự tin vượt qua buổi phỏng vấn.

### 🟢 Mức độ: DỄ (Hiểu khái niệm cốt lõi)

#### **Câu 1: Block `data` trong Terraform dùng để làm gì? Phân biệt nó với block `resource`.**
*   **Trả lời**: 
    *   Block `resource` dùng để khai báo và quản lý vòng đời (tạo, cập nhật, xóa) của một tài nguyên thực tế trên Cloud.
    *   Block `data` (Data Source) là một cơ chế chỉ đọc (read-only). Nó dùng để truy vấn thông tin của các tài nguyên đã tồn tại sẵn bên ngoài hệ thống (do click tay hoặc do dự án khác tạo) để truyền thông tin đó vào code Terraform hiện tại.

#### **Câu 2: Tại sao chúng ta cần chạy lệnh `terraform fmt` và `terraform validate` trong quá trình làm việc?**
*   **Trả lời**:
    *   `terraform fmt` giúp định dạng lại toàn bộ code `.tf` theo chuẩn cú pháp HCL để code sạch sẽ, dễ đọc, thống nhất quy chuẩn viết code giữa các thành viên trong nhóm.
    *   `terraform validate` giúp kiểm tra lỗi cú pháp, kiểu dữ liệu của biến, kiểm tra xem các tài nguyên tham chiếu chéo có tồn tại không. Lệnh này giúp phát hiện lỗi sớm trước khi chạy lệnh `plan` (vốn tốn thời gian vì phải gọi API lên cloud).

---

### 🟡 Mức độ: TRUNG BÌNH (Hiểu cơ chế vận hành)

#### **Câu 3: So sánh sự khác nhau giữa tham số lặp `count` và `for_each`. Khi nào nên dùng loại nào?**
*   **Trả lời**:
    *   `count` sử dụng một số nguyên để tạo ra số lượng tài nguyên tương ứng. Các tài nguyên được phân biệt qua index số (`[0], [1], [2]`).
        *   *Nên dùng*: Khi muốn tạo nhanh các tài nguyên giống hệt nhau hoặc bật/tắt tài nguyên có điều kiện (`count = 0` hoặc `count = 1`).
    *   `for_each` sử dụng một tập hợp (set) hoặc map để tạo tài nguyên. Mỗi tài nguyên được định danh bằng một chuỗi key cụ thể.
        *   *Nên dùng*: Khi tạo các tài nguyên có cấu hình chi tiết khác nhau (ví dụ: tạo nhiều subnet với CIDR block khác nhau).
        *   *Ưu điểm*: Khi xóa một phần tử ở giữa map, Terraform chỉ xóa đúng tài nguyên tương ứng với key đó, không gây ảnh hưởng hay làm dịch chuyển index của các tài nguyên khác như `count`.

#### **Câu 4: Làm thế nào để ẩn các thông tin nhạy cảm (như mật khẩu Database, Access Key) không cho hiển thị trên màn hình Console khi chạy pipeline CI/CD?**
*   **Trả lời**: 
    Ta khai báo thuộc tính `sensitive = true` bên trong khối định nghĩa biến `variable` hoặc khối `output`. 
    Khi chạy `terraform plan` hoặc `terraform apply`, Terraform sẽ tự động ẩn các giá trị này và thay thế bằng chuỗi `(sensitive value)` trên màn hình log console. 
    *Lưu ý*: Giá trị nhạy cảm này vẫn được lưu dưới dạng text thường trong file `terraform.tfstate`, do đó cần bảo mật file state.

---

### 🔴 Mức độ: KHÓ (Vận dụng dự án thực tế)

#### **Câu 5: Trong dự án X-Shop, giả sử một S3 Bucket quan trọng chứa ảnh sản phẩm đã được tạo tay trên AWS Console từ trước. Bây giờ, sếp yêu cầu đưa S3 Bucket này vào quản lý bằng Terraform mà không được làm mất mát dữ liệu hiện có. Quy trình thực hiện như thế nào?**
*   **Trả lời**: Quy trình chuyển dịch một tài nguyên tồn tại sẵn vào quản lý bằng Terraform gồm 3 bước:
    1.  **Khai báo code**: Viết một block `resource "aws_s3_bucket" "product_images" {}` trong file code `.tf` với các thuộc tính khớp đúng cấu hình đang chạy trên AWS Console.
    2.  **Liên kết bằng lệnh `terraform import`** (Hoặc dùng khối `import` trong Terraform 1.5+): Chạy lệnh:
        ```bash
        terraform import aws_s3_bucket.product_images <tên_bucket_thực_tế_trên_aws>
        ```
        Lệnh này sẽ kéo thông tin cấu hình thực tế của bucket về và ghi đè vào file trạng thái `terraform.tfstate`.
    3.  **Đối chiếu kiểm tra**: Chạy `terraform plan`. 
        *   Nếu kết quả báo `No changes. Infrastructure is up-to-date`, nghĩa là code viết ở bước 1 đã khớp hoàn toàn với thực tế và import thành công.
        *   Nếu báo có thay đổi (`+` hoặc `~`), tiến hành điều chỉnh code trong file `.tf` cho khớp hoàn toàn đến khi plan báo không có thay đổi.

#### **Câu 6: Hãy giải thích cách em thiết lập quy trình triển khai Terraform an toàn trong môi trường CI/CD (ví dụ: GitHub Actions). Làm thế nào đảm bảo code hạ tầng được review kỹ lưỡng trước khi apply?**
*   **Trả lời**: Quy trình triển khai an toàn gồm các bước:
    1.  **Nhánh Git**: Phân quyền bảo vệ nhánh `main`. Không cho phép push code trực tiếp, bắt buộc phải thông qua Pull Request (PR).
    2.  **Pipeline khi tạo PR (Plan-on-PR)**: Khi dev tạo PR hướng về nhánh `main`:
        *   Pipeline tự động kích hoạt: Chạy `terraform fmt -check` (kiểm tra định dạng), `terraform validate` (kiểm tra lỗi cú pháp).
        *   Chạy lệnh `terraform plan -out=tfplan` để tạo bản vẽ. Pipeline ghi log đầu ra của lệnh plan này trực tiếp vào phần comment của PR để các kỹ sư SRE khác review đánh giá hạ tầng sắp thay đổi.
    3.  **Phê duyệt**: Bắt buộc phải có ít nhất 1 SRE Lead approve PR.
    4.  **Pipeline khi Merge (Apply-on-merge)**: Khi PR được merge vào nhánh `main`:
        *   Pipeline tự động kích hoạt chạy lệnh `terraform apply -auto-approve tfplan`. Sử dụng file plan đã xuất ở bước PR để đảm bảo hạ tầng được deploy chính xác những gì đã được review, tránh các thay đổi phát sinh ngoài ý muốn giữa thời điểm tạo PR và merge code.
