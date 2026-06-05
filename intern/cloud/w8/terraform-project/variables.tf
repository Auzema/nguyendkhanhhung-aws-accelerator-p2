variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 type - using t4g.small"
  type        = string
  default     = "t4g.medium"
}

variable "project" {
  description = "Name to tag resource"
  type        = string
  default     = "k8s-tf-hung"
}

variable "subnet_cidrs" {
  description = "CIDR block for public subnet"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "my_ip" {
  description = "ip thoi"
  type        = string
}
