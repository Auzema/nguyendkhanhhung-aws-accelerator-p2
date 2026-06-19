variable "aws_region" {
  description = "AWS region for the bucket"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Globally-unique S3 bucket name for media uploads"
  type        = string
  default     = "gitapp-demo-hung"
}

variable "iam_user_name" {
  description = "IAM user the media app uses to access the bucket"
  type        = string
  default     = "media-app"
}
