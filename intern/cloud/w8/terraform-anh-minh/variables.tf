variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 type - x86 nho re"
  type        = string
  default     = "t3.micro"
}

variable "project" {
  description = "Name to tag resource"
  type        = string
  default     = "tf-anh-minh"
}

variable "public_subnet_cidrs" {
  description = "CIDR cho public subnet (2 AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR cho private subnet (2 AZ - RDS subnet group can >=2)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "my_ip" {
  description = "IP cua ban (CIDR /32) - mo SSH chi cho may nay"
  type        = string
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "RDS master password (>=8 ky tu)"
  type        = string
  sensitive   = true
}
