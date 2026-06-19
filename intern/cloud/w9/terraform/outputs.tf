output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.media.bucket
}

output "aws_region" {
  description = "Region the bucket lives in"
  value       = var.aws_region
}

output "access_key_id" {
  description = "Access key id for the media-app IAM user"
  value       = aws_iam_access_key.media_app.id
}

# Sensitive: print with `terraform output -raw secret_access_key`.
# This value also lives in terraform.tfstate — never commit that file.
output "secret_access_key" {
  description = "Secret access key for the media-app IAM user"
  value       = aws_iam_access_key.media_app.secret
  sensitive   = true
}
