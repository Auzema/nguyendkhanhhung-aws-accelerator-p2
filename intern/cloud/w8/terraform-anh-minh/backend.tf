# Remote backend: state luu tren S3, khoa bang DynamoDB (chong 2 nguoi apply cung luc)
# >>> DOI <BUCKET-DUY-NHAT> thanh ten bucket that da tao
terraform {
  backend "s3" {
    bucket         = "tf-anh-minh-tfstate-CHANGEME"
    key            = "w8/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-anh-minh-tflock"
    encrypt        = true
  }
}
