# Hành Trình Terraform Phần 2: Quản Lý Trạng Thái Chuyên Sâu & Thiết Kế Module Chuẩn Hóa

---

## Phần 1: Câu Chuyện Thực Tế — Xung Đột Quốc Tế Trong File State & Code "Copy-Paste"

Sau khi triển khai thành công Terraform cơ bản, Nam cảm thấy vô cùng tự tin. Team SRE (Site Reliability Engineering — kỹ thuật đảm bảo độ tin cậy hệ thống) lúc này đón nhận thêm một thành viên mới tên là **Hoa**.
Mentor Minh giao cho hai bạn nhiệm vụ mở rộng hệ thống X-Shop: Nam chịu trách nhiệm cập nhật Security Group (nhóm bảo mật đóng vai trò tường lửa kiểm soát lưu lượng mạng) để tối ưu hóa bảo mật, còn Hoa cấu hình tăng quy mô (scale) cho EC2 (Elastic Compute Cloud — dịch vụ máy chủ ảo của AWS) instance.

Cả hai làm việc độc lập trên laptop của mình:
1.  Nam sửa code Security Group trên máy mình và chạy `terraform apply`. Quá trình diễn ra suôn sẻ, file `terraform.tfstate` (file lưu trữ trạng thái thực tế của hạ tầng do Terraform quản lý) trên máy Nam được cập nhật.
2.  Cùng lúc đó, Hoa sửa cấu hình Instance Type từ `t3.micro` lên `t3.medium` trên máy cô ấy và chạy `terraform apply`. Vì file `terraform.tfstate` trên máy Hoa không biết những gì Nam vừa làm (nó chỉ lưu trạng thái cũ trước khi Nam sửa), khi Hoa apply, Terraform trên máy Hoa đã đối chiếu với bản state cũ và vô tình đè lên thay đổi Security Group của Nam trên AWS, đưa Security Group về trạng thái cũ.
3.  Khi Nam kiểm tra lại app, lỗi bảo mật lại xảy ra. Cả hai đối chiếu và bàng hoàng nhận ra file state của mình bị lệch nhau hoàn toàn, đè lên nhau gây hỗn loạn hạ tầng AWS. Lỗi này gọi là **State Conflict (Xung đột trạng thái)**.

Chưa dừng lại ở đó, Nam cần nhân bản hệ thống ra 3 môi trường: Dev (Phát triển), Staging (Kiểm thử) và Prod (Sản xuất). Nam bắt đầu sao chép (copy-paste) toàn bộ code VPC (Virtual Private Cloud — mạng ảo riêng tư trên AWS), Subnet, EC2 từ file này sang file khác. Code phình to ra hàng nghìn dòng, cực kỳ khó đọc và chỉ cần một thay đổi nhỏ (ví dụ: thêm một tag mới) là Nam phải đi sửa tay ở cả 3 thư mục.

Mentor Minh liền triệu tập cuộc họp khẩn cấp:
> *"Các em đang đi vào vết xe đổ lớn của vận hành hạ tầng. Thứ nhất, file State phải được quản lý tập trung và khóa lại khi có người sử dụng để tránh ghi đè đồng thời. Thứ hai, không được copy-paste code bừa bãi, hãy sử dụng cơ chế Module hóa để tái sử dụng mã nguồn hạ tầng."*

---

## Phần 2: Quản Lý Trạng Thái Từ Xa (Remote State) & Khóa Trạng Thái (State Locking)

Để giải quyết triệt để vấn đề xung đột state giữa Nam và Hoa, Terraform cung cấp cơ chế lưu trữ state tập trung (Remote Backend) kết hợp khóa trạng thái (State Locking).

```
   Laptop Nam (apply) ───┐                                 ┌─── S3 Bucket (Lưu State file dưới dạng JSON)
                         ├─► [Terraform Backend] ──────────┤
   Laptop Hoa (apply) ───┘   (Đăng ký Lock qua DynamoDB)   └─── DynamoDB Table (Lưu LockID để khóa quyền ghi)
```

### 1. Cấu Hình S3 Backend & DynamoDB Lock trên AWS

Hạ tầng chuẩn trên AWS sử dụng S3 (Simple Storage Service — dịch vụ lưu trữ đối tượng của AWS) Bucket để lưu trữ file state tập trung và bảng DynamoDB (dịch vụ cơ sở dữ liệu NoSQL được quản lý bởi AWS) để thực hiện cơ chế khóa trạng thái (State Locking) nhằm tránh ghi đè đồng thời.

#### Mã nguồn cấu hình Backend trong block `terraform`:
```hcl
# Cấu hình backend không nhận biến (hardcoded variables) theo thiết kế của Terraform
terraform {
  backend "s3" {
    bucket         = "xshop-terraform-state-prod"       # Tên S3 bucket lưu file state
    key            = "global/s3/terraform.tfstate"       # Đường dẫn lưu file state trong bucket
    region         = "ap-southeast-1"                   # Vùng triển khai
    
    dynamodb_table = "xshop-tflocks"                    # Tên bảng DynamoDB dùng để locking
    encrypt        = true                               # Ép buộc mã hóa state file bằng KMS (Key Management Service) phía S3
  }
}
```

### 2. Bài Toán Con Gà - Quả Trứng: Bootstrapping Backend

Một câu hỏi hóc búa thường gặp trong các buổi vấn đáp: **"Làm thế nào để tạo S3 Bucket và DynamoDB Table dùng làm backend nếu chính Terraform cần backend đó để chạy?"**

Có hai giải pháp phổ biến để giải quyết vấn đề vòng lặp này:

#### Cách 1: Tạo thủ công qua AWS CLI (Khuyên dùng cho đơn giản)
Chạy script AWS CLI (Command-Line Interface — giao diện dòng lệnh) trước khi chạy bất kỳ lệnh Terraform nào:
```bash
# Tạo S3 Bucket lưu State
aws s3api create-bucket \
  --bucket xshop-terraform-state-prod \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

# Bật tính năng Versioning cho S3 (Bắt buộc để backup các phiên bản state cũ)
aws s3api put-bucket-versioning \
  --bucket xshop-terraform-state-prod \
  --versioning-configuration Status=Enabled

# Tạo bảng DynamoDB để khóa trạng thái (Bắt buộc Khóa chính/Partition Key tên là LockID kiểu String)
aws dynamodb create-table \
  --table-name xshop-tflocks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-1
```

#### Cách 2: Quy trình dịch chuyển State 2 bước (Mượt mà hơn)
1.  **Bước 1**: Viết code Terraform tạo S3 Bucket và DynamoDB Table nhưng cấu hình backend là `local` (mặc định lưu file state trên máy). Chạy `terraform init` và `terraform apply`.
2.  **Bước 2**: Sau khi hạ tầng S3 và DynamoDB đã được tạo thành công, ta thêm block cấu hình `backend "s3"` ở trên vào code.
3.  **Bước 3**: Chạy lại lệnh:
    ```bash
    terraform init -migrate-state
    ```
    Terraform sẽ tự động phát hiện bạn vừa đổi cấu hình backend, hỏi bạn có muốn di chuyển (migrate) file state cũ từ local lên S3 bucket vừa tạo hay không. Nhập `yes` để hoàn thành.

### 3. Cơ Chế Hoạt Động Của Khóa Trạng Thái (State Locking)

1.  **Gửi yêu cầu khóa**: Khi Hoa chạy lệnh `terraform apply`, Terraform gửi một API call đến DynamoDB để ghi đè một item có ID là `LockID` (giá trị là đường dẫn file state, ví dụ: `xshop-terraform-state-prod/global/s3/terraform.tfstate-md5`). Item này chứa metadata về người chạy, thời gian và ID tiến trình (PID).
2.  **Từ chối truy cập**: Nếu trong lúc này Nam cũng gõ `terraform apply`, Terraform trên máy Nam kiểm tra bảng DynamoDB và thấy `LockID` này đã tồn tại. Hệ thống lập tức báo lỗi và dừng tiến trình:
    ```
    Error: Error acquiring the state lock
    Lock Info:
      ID:        5b5e7d58-9a84-0a37-4d92-23c2a13f28cf
      Path:      xshop-terraform-state-prod/global/s3/terraform.tfstate
      Operation: ActionModify
      Who:       hoa@laptop
      Version:   1.5.0
      Created:   2026-06-21 12:00:00 UTC
    ```
3.  **Giải phóng khóa**: Khi tiến trình của Hoa kết thúc (thành công hoặc thất bại), Terraform tự động gửi lệnh xóa item khóa đó khỏi DynamoDB, đưa hệ thống về trạng thái sẵn sàng nhận lệnh mới.

### 4. Hệ Thống Lệnh Quản Lý State Chuyên Sâu

Khi cấu hình bị trôi lệch hoặc cần cấu trúc lại mã nguồn, SRE tuyệt đối không được mở file `terraform.tfstate` để sửa bằng tay vì cấu trúc JSON rất phức tạp và chỉ cần lệch một dấu phẩy sẽ làm hỏng toàn bộ state. Ta phải dùng các CLI tool chuẩn:

*   **`terraform state list`**: Liệt kê toàn bộ tài nguyên đang được Terraform quản lý.
    ```bash
    $ terraform state list
    aws_instance.web_server
    aws_security_group.web_sg
    module.vpc.aws_vpc.this
    ```
*   **`terraform state show <address>`**: Hiển thị chi tiết các thuộc tính thực tế của một tài nguyên trong file state mà không cần gọi API lên AWS.
    ```bash
    $ terraform state show aws_instance.web_server
    # Hiển thị ID, IP public, AMI, tags, Block Device...
    ```
*   **`terraform state mv <old_address> <new_address>`**: Di chuyển tài nguyên trong file state. Dùng khi đổi tên resource trong code `.tf` hoặc đưa một resource từ Root Module vào trong Child Module. Lệnh này giúp Terraform hiểu đây chỉ là đổi tên logic chứ không phải là xóa đi tạo lại tài nguyên thật trên AWS.
    ```bash
    # Đưa EC2 hiện tại vào quản lý bởi module "web_cluster"
    terraform state mv aws_instance.web_server module.web_cluster.aws_instance.web_server
    ```
*   **`terraform state rm <address>`**: Gỡ bỏ tài nguyên khỏi file state. Tài nguyên ngoài AWS vẫn chạy bình thường nhưng Terraform sẽ không theo dõi nó nữa (tiện lợi khi muốn chuyển quyền quản lý tài nguyên sang một code Terraform khác).
*   **`terraform force-unlock <lock_id>`**: Giải phóng cưỡng bức khóa trạng thái. Dùng khi tiến trình apply của Hoa bị đứt mạng hoặc crash đột ngột làm khóa DynamoDB bị kẹt vô hạn trên cloud. Lấy `Lock ID` từ thông báo lỗi và chạy:
    ```bash
    terraform force-unlock 5b5e7d58-9a84-0a37-4d92-23c2a13f28cf
    ```

---

## Phần 3: Thiết Kế & Sử Dụng Module Trong Terraform

Module là một cách đóng gói nhóm các tài nguyên hạ tầng lại với nhau để tái sử dụng, giúp viết code một lần (DRY — Don't Repeat Yourself) và gọi lại ở nhiều môi trường.

### 1. Cấu Trúc File Chuẩn Của Một Child Module

Một module độc lập và chuẩn hóa luôn phải chứa ít nhất 3 file đặt trong một thư mục:
*   `variables.tf`: Định nghĩa các tham số đầu vào (inputs) để cấu hình linh hoạt.
*   `main.tf`: Khai báo các tài nguyên vật lý thực thi hạ tầng.
*   `outputs.tf`: Định nghĩa các giá trị đầu ra (outputs) để các module khác hoặc root module có thể tham chiếu sử dụng.

#### Ví dụ thiết kế Module VPC (`modules/vpc/`):

**File `modules/vpc/variables.tf`:**
```hcl
variable "vpc_cidr" {
  type        = string
  description = "Địa chỉ CIDR Block cho VPC"
  default     = "10.0.0.0/16" # Giá trị mặc định nếu người dùng không truyền vào
}

variable "subnet_cidrs" {
  type        = list(string)
  description = "Danh sách CIDR Blocks cho các Subnets"
  
  # Cấu hình validation để kiểm tra tính hợp lệ của biến ngay khi compile
  validation {
    condition     = length(var.subnet_cidrs) >= 2
    error_message = "Module yêu cầu tối thiểu phải có 2 Subnet để đảm bảo High Availability."
  }
}

variable "env_name" {
  type        = string
  description = "Tên môi trường (dev, staging, prod)"
}
```

**File `modules/vpc/main.tf`:**
```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  
  tags = {
    Name        = "xshop-vpc-${var.env_name}"
    Environment = var.env_name
  }
}

resource "aws_subnet" "this" {
  count             = length(var.subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  tags = {
    Name        = "xshop-subnet-${var.env_name}-${count.index}"
    Environment = var.env_name
  }
}
```

**File `modules/vpc/outputs.tf`:**
```hcl
output "vpc_id" {
  value       = aws_vpc.this.id
  description = "ID của VPC vừa khởi tạo"
}

output "subnet_ids" {
  value       = aws_subnet.this[*].id
  description = "Danh sách các ID Subnet vừa khởi tạo"
}
```

### 2. Gọi Module Từ Root Module (`envs/dev/main.tf`)

Để sử dụng module vừa thiết kế ở trên, tại thư mục gốc chạy hạ tầng, ta khai báo block `module`:

```hcl
module "network" {
  source = "../../modules/vpc" # Khai báo đường dẫn tương đối tới thư mục chứa module

  # Truyền các biến đầu vào cho module
  vpc_cidr     = "10.0.0.0/16"
  subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  env_name     = "dev"
}

# Lấy đầu ra của module network làm đầu vào cho module compute
module "web_servers" {
  source = "../../modules/ec2"

  instance_type = "t3.micro"
  subnet_id     = module.network.subnet_ids[0] # Tham chiếu trực tiếp tới output vpc_id của module network
  env_name      = "dev"
}
```

### 3. Nguồn Cung Cấp Module (Module Sources)

Terraform hỗ trợ gọi module từ nhiều nguồn khác nhau, giúp quản lý phiên bản và tính bảo mật:

*   **Local Path**: Đường dẫn tương đối (ví dụ: `source = "./modules/vpc"`). Thích hợp khi code module nằm chung trong một repository.
*   **Git Repository**: Tải code trực tiếp từ Github hoặc Gitlab riêng của công ty.
    ```hcl
    module "vpc" {
      # Luôn ghim chặt tag phiên bản qua tham số ?ref để tránh code bị tự động cập nhật gây lỗi hạ tầng
      source = "git::https://github.com/TechX-Corp/terraform-aws-vpc.git?ref=v2.1.0"
    }
    ```
*   **Terraform Registry**: Chợ ứng dụng công cộng của HashiCorp.
    ```hcl
    module "vpc" {
      source  = "terraform-aws-modules/vpc/aws"
      version = "5.1.0" # Chỉ định rõ phiên bản module
    }
    ```

---

## Phần 4: Cấu Trúc Thư Mục Hệ Thống & Quản Lý Đa Môi Trường

Khi vận hành thực tế tại TechX, một câu hỏi quan trọng là: **"Nên quản lý môi trường Dev, Staging, Production qua Terraform Workspaces hay cấu trúc thư mục Directory-based?"**

### 1. So Sánh Chi Tiết Hai Phương Án Thiết Kế

| Đặc điểm | **Terraform Workspaces** | **Directory-based (Thư mục riêng)** |
| :--- | :--- | :--- |
| **Cơ chế** | Dùng chung 1 thư mục code vật lý. Phân chia state bằng câu lệnh quản lý workspace của CLI. | Tách biệt hoàn toàn thành các thư mục độc lập trên ổ đĩa (ví dụ: `envs/dev/`, `envs/prod/`). |
| **Lưu trữ State** | State tự động lưu trong các key con trên S3 backend dưới dạng prefix (ví dụ: `env:/dev/terraform.tfstate`). | File state lưu tại các bucket S3 hoặc key hoàn toàn độc lập, tách biệt vật lý. |
| **Blast Radius (Phạm vi ảnh hưởng lỗi)** | **Rất lớn**. Vì dùng chung 1 file code, một lỗi thay đổi cấu hình nhỏ hoặc gõ nhầm lệnh destroy trên workspace `prod` có thể xóa sạch hệ thống production. | **Cực nhỏ**. Mọi thay đổi trên Dev bị cô lập hoàn toàn trong thư mục dev. Lệnh apply ở dev không thể sờ tới prod. |
| **Phân quyền bảo mật** | Khó phân quyền IAM. Vì dùng chung 1 code và 1 backend cấu hình, người chạy cần có quyền tương tác với toàn bộ backend bucket. | Dễ dàng. Ta có thể phân quyền IAM cho SRE Intern chỉ được đọc/ghi trên thư mục `envs/dev` và bucket state của Dev. |
| **Phân tách AWS Account** | Rất khó cấu hình dùng các AWS Account hoàn toàn khác nhau cho môi trường Dev và Prod. | Rất dễ. Tại `envs/dev/providers.tf` ta khai báo Account Dev, tại `envs/prod/providers.tf` ta khai báo Account Prod. |
| **Độ phù hợp** | Chỉ thích hợp test nhanh, deploy các tài nguyên tạm thời hoặc có cấu trúc giống hệt nhau. | **Chuẩn Production**. Khuyến nghị áp dụng cho mọi dự án lớn cần an toàn bảo mật tuyệt đối. |

### 2. Cấu Trúc Thư Mục Khuyến Nghị Cho Dự Án
```
xshop-infrastructure/
├── modules/               # Nơi chứa các Child Module dùng chung
│   ├── vpc/
│   │   ├── main.tf, variables.tf, outputs.tf
│   ├── ec2/
│   └── rds/
└── envs/                  # Nơi chứa cấu hình thực thi của từng môi trường (Root Modules)
    ├── dev/
    │   ├── backend.tf     # Cấu hình S3 Backend trỏ về Dev bucket
    │   ├── main.tf        # Gọi các module từ thư mục modules/ truyền biến của Dev
    │   ├── variables.tf
    │   └── terraform.tfvars # Chứa giá trị thực tế của biến môi trường Dev
    └── prod/
        ├── backend.tf     # Cấu hình S3 Backend trỏ về Prod bucket (riêng biệt)
        ├── main.tf        # Gọi các module truyền biến cấu hình Prod (size to hơn, multi-AZ)
        ├── variables.tf
        └── terraform.tfvars
```

---

## Phần 5: Quản Lý Bí Mật (Secrets Management) Trong Terraform

Một sai lầm phổ biến nhất của các kỹ sư junior là đẩy trực tiếp Access Key, Secret Key hoặc mật khẩu cơ sở dữ liệu lên Github. Đây là mục tiêu quét hàng đầu của tin tặc.

### 1. Quy Tắc Không Lưu Mật Khẩu Vào Mã Nguồn
*   **Ghi file `.gitignore`**: Luôn thêm các file chứa giá trị biến thực tế như `*.tfvars`, `*.tfvars.json` và các file state cục bộ `*.tfstate`, `.terraform/` vào file cấu hình `.gitignore`.
*   **Sử dụng biến môi trường hệ điều hành**:
    Nếu trong code khai báo biến mật khẩu:
    ```hcl
    variable "db_password" {
      type      = string
      sensitive = true # Ẩn giá trị trong log hiển thị của console
    }
    ```
    Ta sẽ truyền giá trị này tại máy trạm hoặc trong pipeline CI/CD bằng cách xuất biến hệ điều hành với tiền tố **`TF_VAR_`**:
    ```bash
    export TF_VAR_db_password="SuperSecretPassword123"
    terraform apply -auto-approve
    ```
    Terraform sẽ tự động ánh xạ giá trị của `TF_VAR_db_password` vào biến `db_password` trong code.

### 2. Đọc Secrets Động Từ AWS Secrets Manager
Cách bảo mật nhất để truyền secrets là để Terraform tự truy vấn trực tiếp từ dịch vụ quản lý key của Cloud provider tại thời điểm khởi chạy bằng khối **Data Source**.

```hcl
# 1. Truy vấn thông tin của Secret đã có sẵn trên AWS
data "aws_secretsmanager_secret" "db_secret" {
  name = "xshop/production/database"
}

# 2. Lấy phiên bản giá trị mới nhất của Secret đó
data "aws_secretsmanager_secret_version" "db_secret_ver" {
  secret_id = data.aws_secretsmanager_secret.db_secret.id
}

# 3. Giải mã JSON và nạp mật khẩu vào biến local để sử dụng
locals {
  db_credentials = jsondecode(data.aws_secretsmanager_secret_version.db_secret_ver.secret_string)
}

# 4. Sử dụng mật khẩu cho tài nguyên RDS
resource "aws_db_instance" "database" {
  allocated_storage      = 20
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  db_name                = "xshopdb"
  username               = "admin"
  password               = local.db_credentials["password"] # Đọc trực tiếp từ AWS Secrets Manager
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true
}
```

### 3. Cảnh Báo Quan Trọng Về Biến Sensitive
Khi thiết lập `sensitive = true` trên một biến, Terraform sẽ ẩn giá trị của biến đó trên giao diện dòng lệnh khi chạy plan/apply (hiển thị dạng `(sensitive value)`). 

> [!WARNING]
> Thuộc tính `sensitive` **chỉ có tác dụng ẩn thông tin trên màn hình CLI**. Toàn bộ giá trị nhạy cảm đó **vẫn được lưu dưới dạng bản rõ (plaintext) không mã hóa** trong file `terraform.tfstate`. Do đó, bất kỳ ai có quyền đọc file state trên S3 đều có thể xem được mật khẩu.
> **Giải pháp khắc phục**: Phải bật mã hóa S3 Bucket bằng KMS Key và siết chặt quyền truy cập S3 qua IAM Policy.

---

## Phần 6: Tài Liệu Ghi Nhận Quyết Định Kiến Trúc (Architecture Decision Record)

Khi thiết kế hạ tầng hạ tầng dự án X-Shop, nhóm SRE cần ghi lại các quyết định kỹ thuật cốt lõi bằng tài liệu ADR để đảm bảo tính đồng nhất kiến trúc và hỗ trợ chuyển giao kỹ thuật.

### ADR 002: Lựa Chọn Mô Hình Directory-Based Cho Việc Quản Lý Đa Môi Trường

#### Trạng thái
Đã duyệt (Approved)

#### Người thực hiện
Kỹ sư: Nam (SRE Intern) & Hoa (SRE)
Người duyệt: Mentor Minh (SRE Lead)

#### Bối cảnh (Context)
Dự án X-Shop đang mở rộng quy mô từ một môi trường thử nghiệm duy nhất lên ba môi trường: Dev, Staging và Production. Hệ thống đòi hỏi tính cô lập an toàn cao, giảm thiểu rủi ro khi thay đổi hạ tầng giữa các môi trường, đồng thời dễ dàng cấu hình quyền truy cập IAM khác nhau cho từng môi trường (ví dụ: thực tập sinh chỉ có quyền sửa Dev, không có quyền sờ vào Prod). 

Chúng tôi đã xem xét hai phương án thiết kế chính:
1.  **Phương án 1**: Sử dụng Terraform Workspaces (chung thư mục code, phân tách state logic qua CLI).
2.  **Phương án 2**: Sử dụng cấu trúc Directory-based (mỗi môi trường là một thư mục riêng biệt).

#### Quyết định (Decision)
Chúng tôi quyết định lựa chọn **Phương án 2: Mô hình Directory-based**.
*   Mỗi môi trường sẽ được tổ chức độc lập trong thư mục `envs/<env_name>/`.
*   Mỗi thư mục môi trường sẽ khai báo và quản lý một tệp tin cấu hình backend S3 và DynamoDB Lock riêng biệt.
*   Các mã nguồn hạ tầng chung được đóng gói thành các Module dùng chung đặt tại thư mục `modules/`.

#### Hệ quả (Consequences)
*   **Tích cực**:
    *   **Blast Radius cô lập hoàn toàn**: Lỗi phát sinh trong quá trình chạy lệnh apply trên Dev không thể tác động hay gây sập môi trường Production.
    *   **Phân quyền bảo mật tối đa**: Dễ dàng cấu hình chính sách IAM để ngăn chặn tài khoản của kỹ sư Dev truy cập vào S3 bucket chứa state file của môi trường Prod.
    *   **Sử dụng đa tài khoản Cloud**: Cho phép môi trường Dev chạy trên AWS Account Test, và môi trường Prod chạy trên AWS Account Prod thực tế để cô lập hóa đơn và tài nguyên.
*   **Hạn chế**:
    *   Phát sinh việc lặp lại nhẹ mã nguồn khi khai báo gọi module (main.tf) ở từng thư mục môi trường. Kỹ sư phải thực hiện lệnh `terraform init` riêng biệt cho từng thư mục khi làm việc.

---

### ADR 003: Cấu Hình Remote State S3 Kết Hợp Khóa Trạng Thái Qua DynamoDB

#### Trạng thái
Đã duyệt (Approved)

#### Bối cảnh (Context)
Khi số lượng kỹ sư trong team SRE tăng lên (Nam và Hoa làm việc cùng nhau), việc lưu trữ tệp tin trạng thái `terraform.tfstate` tại máy trạm cá nhân (local state) dẫn đến các thảm họa:
*   Mất mát dữ liệu khi hỏng ổ cứng máy trạm.
*   Không đồng bộ cấu hình khiến người này đè cấu hình lên người kia.
*   Hạ tầng bị thay đổi đồng thời khi cả hai kỹ sư cùng chạy `terraform apply` một lúc, gây lỗi không nhất quán dữ liệu (race conditions).

#### Quyết định (Decision)
Chúng tôi quyết định chuyển đổi toàn bộ dự án sang sử dụng **Remote Backend** sử dụng:
*   **Amazon S3**: Làm nơi lưu trữ tập trung file state, kích hoạt tính năng **Bucket Versioning** để tự động lưu lại các bản backup cũ của file state đề phòng trường hợp bị lỗi hoặc ghi đè ngoài ý muốn.
*   **Amazon DynamoDB**: Làm cơ chế khóa trạng thái (State Locking).

#### Hệ quả (Consequences)
*   **Tích cực**:
    *   **An toàn dữ liệu**: State được lưu trữ tập trung trên S3 với độ bền cao (99.999999999% durability).
    *   **Ngăn chặn xung đột**: DynamoDB tự động chặn và khóa các lệnh apply chạy đồng thời, loại bỏ hoàn toàn nguy cơ đè chồng cấu hình.
    *   **Bảo mật dữ liệu**: State được tự động mã hóa ở chế độ nghỉ (Encryption at rest) bằng KMS Key trên S3.
*   **Hạn chế**:
    *   Tăng thêm một bước chuẩn bị hạ tầng ban đầu (phải tạo S3 bucket và DynamoDB table trước khi init).
    *   Yêu cầu kết nối mạng liên tục với AWS khi làm việc với Terraform CLI.
