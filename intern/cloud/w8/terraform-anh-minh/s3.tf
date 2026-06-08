data "aws_caller_identity" "current" {}

# Bucket chua static asset. Ten = project + account-id -> unique toan cau.
resource "aws_s3_bucket" "assets" {
  bucket        = "${var.project}-assets-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # destroy xoa luon object ben trong
  tags          = { Name = "${var.project}-assets" }
}

# Chan moi truy cap public -> bucket PRIVATE. EC2 lay qua IAM role, khong qua URL public.
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload asset mau (video) len bucket.
resource "aws_s3_object" "asset" {
  bucket = aws_s3_bucket.assets.id
  key    = "yes_web.mp4"
  source = "${path.module}/yes_web.mp4"
  etag   = filemd5("${path.module}/yes_web.mp4")
}
