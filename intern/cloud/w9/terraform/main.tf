terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---- S3 bucket that the media app uploads to ----
resource "aws_s3_bucket" "media" {
  bucket = var.bucket_name
}

# Keep the bucket private. The media app serves objects via presigned URLs,
# so public access is NOT needed.
resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---- IAM user scoped to ONLY this bucket (least privilege) ----
resource "aws_iam_user" "media_app" {
  name = var.iam_user_name
}

resource "aws_iam_user_policy" "media_s3" {
  name = "media-s3"
  user = aws_iam_user.media_app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.media.arn,
          "${aws_s3_bucket.media.arn}/*",
        ]
      }
    ]
  })
}

resource "aws_iam_access_key" "media_app" {
  user = aws_iam_user.media_app.name
}
