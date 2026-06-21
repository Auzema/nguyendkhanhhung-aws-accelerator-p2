# Hành Trình Terraform Phần 1: Phá Bỏ Cơn Ác Mộng "Click Tay"

---

## Phần 1: Câu Chuyện Thực Tế — Cơn Ác Mộng Click-Tay & Trôi Lệch Cấu Hình

Vào một buổi sáng thứ Hai đẹp trời, Mentor Minh giao cho Nam — một SRE (Site Reliability Engineering — kỹ sư đảm bảo độ tin cậy hệ thống) Intern mới gia nhập dự án X-Shop — nhiệm vụ đầu tiên:
> *"Nam ơi, em lên AWS (Amazon Web Services — dịch vụ điện toán đám mây của Amazon) tạo cho anh một hạ tầng cơ bản để chạy ứng dụng nhé. Gồm có: 1 VPC (Virtual Private Cloud — mạng ảo riêng tư trên AWS), 1 Subnet (phân vùng mạng con trong VPC), 1 EC2 (Elastic Compute Cloud — dịch vụ máy ảo trên AWS) Instance đóng vai trò Web Server và 1 S3 (Simple Storage Service — dịch vụ lưu trữ đối tượng trên AWS) Bucket để lưu ảnh sản phẩm."*

Nam đăng nhập vào trang quản trị AWS Console, bắt đầu cuộc hành trình "click chuột":
1. Tìm dịch vụ VPC $\rightarrow$ Click Create VPC $\rightarrow$ Điền IP (Internet Protocol — giao thức internet) CIDR (Classless Inter-Domain Routing — phương pháp định tuyến và phân chia địa chỉ IP).
2. Tìm dịch vụ EC2 $\rightarrow$ Chọn AMI (Amazon Machine Image — bản mẫu máy ảo cấu hình sẵn trên AWS), chọn size `t3.micro` $\rightarrow$ Tạo Key Pair (cặp khóa bảo mật dùng để đăng nhập máy chủ từ xa) $\rightarrow$ Cấu hình Security Group (nhóm bảo mật đóng vai trò tường lửa kiểm soát lưu lượng truy cập) mở cổng 80 và 22.
3. Tìm dịch vụ S3 $\rightarrow$ Tạo bucket với tên `xshop-product-images-dev` $\rightarrow$ Tắt Block Public Access để hiển thị ảnh.

Sau gần 2 tiếng đồng hồ vừa click vừa tra cứu, Nam tự hào báo cáo hoàn thành. Mọi thứ chạy trơn tru.

### Bước Ngoặt Xuất Hiện
Mentor Minh mỉm cười gật đầu: 
> *"Tốt lắm Nam. Bây giờ, khách hàng muốn có thêm một môi trường **Staging** để QC (Quality Control — bộ phận kiểm thử chất lượng) test, và một môi trường **Production** để chạy thật. Em tạo thêm 2 môi trường giống hệt Dev giúp anh nhé."*

Nam bắt đầu toát mồ hôi. Cậu lại tiếp tục hành trình click chuột. Nhưng lần này:
* Ở môi trường **Staging**: Cậu lỡ tay gõ nhầm IP CIDR của Subnet, dẫn đến việc ứng dụng không thể kết nối tới Database. Cậu tốn thêm 1 tiếng để rà soát lỗi.
* Ở môi trường **Production**: Cậu quên không mở cổng 80 trên Security Group, khiến khách hàng không truy cập được vào Web Server.
* Tồi tệ hơn, một developer khác trong team vì muốn sửa lỗi gấp trong đêm đã tự ý lên AWS Console đổi cấu hình của S3 Bucket mà không báo trước. Khi Nam chạy lại hệ thống, mọi thứ đổ vỡ mà không rõ nguyên nhân. Hiện tượng trôi lệch thực tế này được gọi là **Drift (Trôi lệch cấu hình)**.

Để giải quyết triệt để các vấn đề trên, Mentor Minh yêu cầu Nam chuyển dịch toàn bộ sang **Infrastructure as Code (IaC — hạ tầng dưới dạng mã nguồn)** sử dụng **Terraform** (công cụ IaC nguồn mở phổ biến của HashiCorp). Kể từ đây, mọi hạ tầng của dự án sẽ được khai báo bằng code, lưu trữ lịch sử trên Git và kiểm soát nghiêm ngặt.

---

## Phần 2: Tài Liệu Kỹ Thuật Chuyên Sâu về Cú Pháp HCL (HashiCorp Configuration Language — ngôn ngữ cấu hình của HashiCorp)

Dưới đây là phần phân tích kỹ thuật nghiêm túc và chi tiết về toàn bộ cú pháp HCL (HashiCorp Configuration Language — ngôn ngữ cấu hình của HashiCorp) được áp dụng trong Terraform.

### 1. Khối Cấu Hình Hệ Thống (Terraform Block)
Khối `terraform {}` chứa các cài đặt cốt lõi của chính Terraform, bao gồm phiên bản Terraform yêu cầu và các provider cần thiết.

```hcl
terraform {
  required_version = ">= 1.5.0" # Ràng buộc phiên bản Terraform CLI (Command-Line Interface — giao diện dòng lệnh)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Ràng buộc phiên bản Provider (nhà cung cấp dịch vụ cloud như AWS, Azure, Google Cloud) (chỉ cho phép nâng cấp minor version)
    }
  }
}
```

### 2. Khối Nhà Cung Cấp (Provider Block)
Đóng vai trò dịch mã HCL thành các lệnh gọi API của nhà cung cấp cloud tương ứng.

```hcl
provider "aws" {
  region = "ap-southeast-1"
  
  # Cấu hình Default Tags tự động áp dụng tag cho tất cả tài nguyên được tạo bởi provider này
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "xshop"
      ManagedBy   = "Terraform"
    }
  }
}
```

### 3. Khối Tài Nguyên (Resource Block)
Khai báo tài nguyên vật lý sẽ được khởi tạo trên cloud.

```hcl
resource "aws_instance" "web_server" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  # Tham chiếu động đến thuộc tính của một tài nguyên khác
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
}
```

### 4. Nguồn Dữ Liệu Đọc (Data Source Block)
Truy vấn thông tin từ các tài nguyên đã tồn tại sẵn trên cloud để sử dụng lại trong code mà không quản lý vòng đời của chúng.

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
  
  # Block Validation: Ràng buộc giá trị hợp lệ của biến ngay khi biên dịch
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Giá trị môi trường phải thuộc danh sách: dev, staging, prod."
  }
}
```

### 6. Giá Trị Địa Phương (Locals Block)
Đóng vai trò như các biến số hoặc hằng số nội bộ giúp gộp các biểu thức phức tạp hoặc lặp đi lặp lại để tái sử dụng, giúp code sạch và dễ bảo trì.

```hcl
locals {
  name_prefix = "xshop-${var.environment}"
  common_tags = {
    Owner = "SRE-Team"
    Dept  = "Engineering"
  }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = "${local.name_prefix}-logs"
  tags   = local.common_tags
}
```

### 7. Khối Đầu Ra (Outputs Block)
Trả về các thông tin hữu ích sau khi triển khai thành công hạ tầng.

```hcl
output "web_public_ip" {
  value       = aws_instance.web_server.public_ip
  description = "Địa chỉ IP công cộng của Web Server"
}

output "db_connection_string" {
  value       = "mongodb://${aws_instance.db.private_ip}:27017"
  sensitive   = true # Ẩn thông tin nhạy cảm ở đầu ra
}
```

---

## Phần 3: Biến, Vòng Lặp & Câu Lệnh Điều Kiện trong HCL

### 1. Toán Tử Điều Kiện (Ternary Operator)
Cú pháp: `condition ? true_val : false_val`

```hcl
resource "aws_instance" "app" {
  ami                         = "ami-0c55b159cbfafe1f0"
  instance_type               = "t3.micro"
  associate_public_ip_address = var.environment == "prod" ? false : true
}
```

### 2. Vòng Lặp Với Tham Số `count`
Tạo ra một danh sách các tài nguyên giống nhau bằng index số (`count.index`).
```hcl
resource "aws_instance" "web" {
  count         = 3
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  tags = {
    Name = "web-server-${count.index}" # Tạo ra web-server-0, web-server-1, web-server-2
  }
}
```

### 3. Vòng Lặp Với Tham Số `for_each`
Lặp qua một tập hợp (set) hoặc một bản đồ (map) để tạo ra các tài nguyên định danh bằng các chuỗi khóa (key) cụ thể thay vì chỉ số thứ tự. Đây là giải pháp khuyến nghị vì nó giúp tránh việc hủy/tạo lại tài nguyên ngoài ý muốn khi sửa đổi các phần tử ở giữa danh sách.

```hcl
resource "aws_subnet" "public" {
  for_each          = var.subnets_config # Map chứa subnet_name và cấu hình
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = {
    Name = "subnet-${each.key}"
  }
}
```

### 4. Biểu Thức Vòng Lặp Trong Giá Trị (For Expressions & Splat)
Biến đổi dữ liệu danh sách hoặc map trực tiếp trong code.
```hcl
# Trích xuất toàn bộ ARN từ danh sách IAM users và viết hoa tên
output "uppercase_user_names" {
  value = [for u in aws_iam_user.users : upper(u.name)]
}

# Splat Operator (*) để lấy nhanh danh sách ID
output "instance_ids" {
  value = aws_instance.web[*].id
}
```

---

## Phần 4: Các Tham Số Siêu Cấu Hình (Meta-Arguments)

Meta-arguments cấu hình cách thức vận hành và quản lý tài nguyên của Terraform.

### 1. Phụ Thuộc Rõ Ràng (`depends_on`)
Ép buộc Terraform phải hoàn thành tài nguyên này trước khi bắt đầu tạo tài nguyên kia, áp dụng khi không có quan hệ tham chiếu trực tiếp trong code nhưng có sự phụ thuộc về mặt logic nghiệp vụ (ví dụ: tạo EKS Cluster chỉ sau khi IAM Role được cấu hình xong).

```hcl
resource "aws_eks_cluster" "aws_eks" {
  name     = "xshop-eks"
  role_arn = aws_iam_role.eks_role.arn
  depends_on = [
    aws_iam_role.eks_role
  ]
}
```

### 2. Quản Lý Vòng Đời Tài Nguyên (`lifecycle` block)
*   **`create_before_destroy = true`**: Thay đổi mặc định của Terraform. Thay vì xóa tài nguyên cũ trước rồi mới tạo tài nguyên mới, nó sẽ tạo tài nguyên mới chạy ổn định rồi mới xóa tài nguyên cũ nhằm giảm thiểu tối đa thời gian downtime hệ thống.
*   **`prevent_destroy = true`**: Chặn đứng mọi hành vi xóa tài nguyên này khi chạy lệnh `destroy`. Thích hợp bảo vệ Database, S3 Bucket lưu data quan trọng.
*   **`ignore_changes = [...]`**: Bỏ qua các thay đổi đối với một số thuộc tính cụ thể khi đối chiếu trạng thái. Thích hợp khi thuộc tính đó được thay đổi tự động bên ngoài cloud (ví dụ: Auto Scaling điều chỉnh số lượng máy chủ, hoặc tags được gán tự động bởi AWS Control Tower).

---

## Phần 5: Hệ Thống Lệnh CLI (Command-Line Interface — giao diện dòng lệnh) Chuyên Sâu & Môi Trường Vận Hành

Hệ thống lệnh CLI của Terraform hỗ trợ kiểm soát toàn diện vòng đời hạ tầng và xử lý sự cố.

### 1. Nhóm Lệnh Khởi Tạo & Định Dạng (Initialization & Validation)
*   **`terraform init`**: Khởi tạo thư mục làm việc, tải các Provider plugins được định nghĩa trong code về thư mục ẩn `.terraform/`.
    *   `-upgrade`: Ép buộc tải phiên bản mới nhất của Provider nằm trong khoảng ràng buộc cho phép trong code.
    *   `-backend-config="path/to/backend.tfvars"`: Cấu hình backend (S3, Consul) động tại thời điểm khởi chạy, tách biệt cấu hình backend khỏi code gốc.
*   **`terraform fmt`**: Tự động chuẩn hóa định dạng, căn lề toàn bộ file `.tf` theo tiêu chuẩn HCL.
    *   `-check`: Kiểm tra xem các file đã được định dạng đúng chuẩn chưa nhưng không ghi đè thay đổi (thường dùng trong bước kiểm tra của CI (Continuous Integration - tích hợp liên tục) pipeline).
*   **`terraform validate`**: Kiểm tra tính hợp lệ về mặt cú pháp và logic liên kết của code mà không cần truy vấn hạ tầng thực tế.

### 2. Nhóm Lệnh Triển Khai & Bản Vẽ Hạ Tầng (Execution Workflow)
*   **`terraform plan`**: Đối chiếu hạ tầng thực tế, so sánh với code và sinh ra bản vẽ thay đổi.
    *   `-out=path/to/file.tfplan`: Xuất bản vẽ ra một file nhị phân cụ thể. Đảm bảo tính toàn vẹn của kế hoạch triển khai, ngăn chặn việc hạ tầng thực tế bị thay đổi bởi tác nhân khác giữa lúc plan và apply.
    *   `-var="key=value"` hoặc `-var-file="path.tfvars"`: Truyền giá trị cho các biến đầu vào trực tiếp từ CLI.
    *   `-detailed-exitcode`: Trả về exit code chi tiết (0: không thay đổi, 2: có thay đổi hạ tầng, 1: lỗi). Dùng để lập trình logic tự động hóa trong CI/CD (Continuous Integration/Continuous Delivery - tích hợp và phân phối liên tục).
    *   `-replace="aws_instance.web[0]"`: (Thay thế lệnh `taint` cũ từ v0.15.2+) Đánh dấu tài nguyên cụ thể sẽ bị hủy và tạo lại ngay trong lượt apply tiếp theo mà không làm ảnh hưởng các tài nguyên khác.
*   **`terraform apply`**: Thực thi thay đổi lên cloud.
    *   `path/to/file.tfplan`: Triển khai trực tiếp từ file bản vẽ đã xuất ở bước plan mà không cần hỏi lại xác nhận `yes`. Đây là cách triển khai chuẩn trong môi trường sản xuất.
    *   `-auto-approve`: Tự động đồng ý triển khai mà không cần nhập `yes` trên console.
    *   `-target=aws_instance.web`: Chỉ áp dụng thay đổi cho một tài nguyên duy nhất được chỉ định (khuyến cáo hạn chế sử dụng vì có thể phá vỡ đồ thị phụ thuộc của hạ tầng).
*   **`terraform destroy`**: Hủy toàn bộ tài nguyên được quản lý bởi cấu hình Terraform hiện hành.
    *   `-auto-approve`: Bỏ qua xác nhận xác thực.
    *   `-target=...`: Chỉ hủy một tài nguyên cụ thể.

### 3. Nhóm Lệnh Quản Lý Trạng Thái (State Management)
*   **`terraform state`**: Bộ lệnh can thiệp và điều chỉnh trực tiếp file `terraform.tfstate`.
    *   `state list`: Liệt kê tất cả các tài nguyên đang được Terraform quản lý trong file state.
    *   `state show <resource_address>`: Hiển thị toàn bộ thông tin chi tiết (các tham số và giá trị thực tế) của một tài nguyên cụ thể trong state.
    *   `state mv <old_address> <new_address>`: Đổi tên logic của tài nguyên trong file state. Dùng khi ta cấu trúc lại code (refactor) và đổi tên tài nguyên trong file `.tf` nhưng không muốn Terraform hủy và tạo mới tài nguyên đó ngoài thực tế.
    *   `state rm <resource_address>`: Gỡ bỏ tài nguyên khỏi file state. Tài nguyên ngoài cloud vẫn tồn tại nhưng Terraform sẽ không còn theo dõi hay quản lý nữa.
*   **`terraform import <resource_address> <cloud_id>`**: Nhập thông tin cấu hình của một tài nguyên được tạo thủ công ngoài cloud vào file state của Terraform.
*   **`terraform refresh`**: (Hạn chế dùng trực tiếp, vì plan/apply đã tự động tích hợp refresh) Truy vấn trạng thái thực tế của tài nguyên trên cloud và cập nhật vào file state cục bộ để phát hiện kịp thời sự trôi lệch cấu hình.
*   **`terraform force-unlock <lock_id>`**: Giải phóng cơ chế khóa trạng thái (State Lock) khi có sự cố xảy ra làm tiến trình apply bị ngắt quãng giữa chừng (ví dụ: máy chạy CI mất kết nối) khiến file state bị khóa vô hạn.

### 4. Nhóm Lệnh Quản Lý Workspace (Multi-environment Workspaces)
*   **`terraform workspace`**: Quản lý nhiều trạng thái hạ tầng khác nhau (ví dụ: Dev, Staging, Prod) một cách độc lập trong cùng một thư mục cấu hình code `.tf`.
    *   `workspace list`: Liệt kê tất cả các workspace hiện có của dự án.
    *   `workspace select <workspace_name>`: Chuyển đổi ngữ cảnh làm việc sang workspace được chỉ định.
    *   `workspace new <workspace_name>`: Tạo mới một workspace trống hoàn toàn.
    *   `workspace delete <workspace_name>`: Xóa một workspace không còn sử dụng (chỉ thực hiện được khi đang ở workspace khác).
    *   `workspace show`: Hiển thị tên workspace đang hoạt động hiện tại. Trong code HCL, ta có thể tham chiếu trực tiếp qua biến `${terraform.workspace}` để đặt tên tài nguyên động tương thích theo từng môi trường.

### 5. Nhóm Lệnh Phân Tích & Tiện Ích (Analysis & Utility)
*   **`terraform console`**: Mở môi trường dòng lệnh tương tác (REPL) để viết và thử nghiệm các biểu thức HCL, kiểm tra cách hoạt động của các hàm build-in (như `merge`, `concat`, `lookup`) trên dữ liệu thực tế mà không cần chạy apply.
*   **`terraform output`**: Trích xuất các giá trị khai báo trong block `output` từ file state.
    *   `-json`: Xuất đầu ra dưới dạng cấu trúc dữ liệu JSON phục vụ việc parse dữ liệu tự động cho các công cụ khác.
*   **`terraform graph`**: Sinh ra sơ đồ dạng đồ thị thể hiện mối quan hệ phụ thuộc lẫn nhau giữa các tài nguyên dưới định dạng DOT, giúp trực quan hóa kiến trúc hệ thống.
*   **`terraform providers`**: Liệt kê chi tiết các providers được yêu cầu và đang được sử dụng trong project để kiểm soát tính tương thích.

### 6. Nhóm Lệnh Xác Thực (Authentication)
*   **`terraform login`**: Đăng nhập và xác thực với Terraform Cloud (TFC) hoặc Terraform Enterprise (TFE), tự động lấy và lưu API token vào file cấu hình local (`~/.terraform.d/credentials.tfrc.json`).
*   **`terraform logout`**: Đăng xuất và xóa API token đã lưu cục bộ trên máy tính.

### 7. Biến Môi Trường Điều Khiển (Terraform Environment Variables)
*   **`TF_LOG`**: Bật chế độ ghi nhật ký debug của Terraform. Các mức độ chi tiết tăng dần: `INFO`, `WARNING`, `ERROR`, `DEBUG`, `TRACE` (dùng khi cần tìm lỗi giao tiếp API giữa Terraform và Cloud provider).
*   **`TF_LOG_PATH`**: Đường dẫn chỉ định lưu file log debug ra đĩa.
*   **`TF_VAR_<variable_name>`**: Định nghĩa giá trị cho biến Terraform thông qua biến môi trường của hệ điều hành (ví dụ: chạy lệnh `export TF_VAR_environment="prod"` trước khi chạy plan).
*   **`TF_DATA_DIR`**: Thay đổi thư mục lưu trữ dữ liệu làm việc của dự án (mặc định là thư mục ẩn `.terraform/`).

---

## Phần 6: Tích Hợp Thực Tế & Các Tình Huống Vận Dụng Dự Án

### 1. Quy Trình Import Tài Nguyên Tạo Tay (Console) Vào Code
Khi hệ thống có sẵn các tài nguyên được tạo thủ công (click tay) từ trước, ta phải đưa chúng vào quản lý tập trung bằng code mà không được gây mất mát dữ liệu hoặc downtime.

#### Luồng xử lý:
1.  **Khai báo Resource rỗng**: Viết một block resource trong code `.tf` của bạn với tên logic mong muốn.
    ```hcl
    resource "aws_s3_bucket" "existing_bucket" {
      # Để trống các cấu hình bên trong hoặc chỉ ghi các tham số cơ bản nhất
    }
    ```
2.  **Chạy lệnh Import**: Liên kết tài nguyên thực tế với block code vừa viết bằng lệnh:
    ```bash
    terraform import aws_s3_bucket.existing_bucket my-manual-bucket-name
    ```
3.  **Đồng bộ cấu hình**: Chạy lệnh `terraform plan`. Lúc này, Terraform sẽ thông báo sự sai lệch vì code của bạn đang rỗng trong khi thực tế bucket có cấu hình.
4.  **Cập nhật code**: Đọc chi tiết log của plan, bổ sung các tham số vào block code ở bước 1 cho đến khi chạy `terraform plan` báo kết quả:
    `No changes. Infrastructure is up-to-date.`
    Lúc này, tài nguyên đã hoàn toàn thuộc quyền quản lý của Terraform.

### 2. Xử Lý Xung Đột State Lock Trong Môi Trường Làm Việc Nhóm
Khi hai kỹ sư SRE cùng chạy `terraform apply` một lúc, hoặc khi pipeline CI đang chạy thì một người khác cố tình sửa đổi hạ tầng.

#### Cơ chế hoạt động:
*   Mỗi khi có lệnh làm thay đổi hạ tầng, Terraform gửi một yêu cầu khóa (lock) lên backend (ví dụ: ghi một record vào bảng DynamoDB).
*   Nếu có người khác đang chạy apply, Terraform sẽ phát hiện file state đang bị khóa và chặn đứng thao tác của người thứ hai để tránh việc ghi đè đè lên nhau gây hỏng file state (corrupted state).

#### Xử lý sự cố State Lock bị kẹt vô hạn:
Trong trường hợp tiến trình apply bị crash (mất mạng, mất điện giữa chừng) nhưng chưa kịp gửi lệnh giải phóng khóa (unlock), hệ thống sẽ báo lỗi khóa file state khi có người chạy lệnh tiếp theo.
1.  Lấy mã khóa `ID` (Lock ID) từ thông báo lỗi trên terminal.
2.  Xác minh chắc chắn không có ai khác đang thực sự deploy hạ tầng.
3.  Chạy lệnh giải phóng cưỡng bức:
    ```bash
    terraform force-unlock <LOCK_ID>
    ```

### 3. Tận Dụng Biến Nhạy Cảm & Tách Biệt Môi Trường
Để tránh lộ thông tin bảo mật khi chạy Terraform trong môi trường tự động hóa:
*   Sử dụng biến môi trường hệ thống để truyền thông tin nhạy cảm thay vì ghi trực tiếp vào code. Ví dụ: `export TF_VAR_db_password="SuperSecretPassword"`.
*   Tách biệt hoàn toàn file state của các môi trường (Dev, Staging, Production) bằng cách sử dụng các backend bucket khác nhau hoặc cấu hình tiền tố khóa (key prefix) khác nhau trên S3.
*   Cấu hình KMS (Key Management Service - dịch vụ quản lý khóa mã hóa của AWS) Key để mã hóa dữ liệu của file `terraform.tfstate` khi lưu trữ trên S3 Backend, vì file state chứa toàn bộ thông tin tài nguyên dưới dạng bản rõ (cleartext), kể cả các biến được đánh dấu `sensitive`.
