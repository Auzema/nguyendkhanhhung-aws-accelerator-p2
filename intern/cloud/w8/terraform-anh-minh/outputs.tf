output "web_url" {
  description = "Mo browser kiem tra web (bang chung nop bai)"
  value       = "http://${aws_eip.web.public_ip}"
}

output "ec2_public_ip" {
  description = "Elastic IP cua EC2"
  value       = aws_eip.web.public_ip
}

output "ssh_command" {
  description = "Lenh SSH vao EC2"
  value       = "ssh -i ${path.module}/${var.project}-key.pem ec2-user@${aws_eip.web.public_ip}"
}

output "rds_endpoint" {
  description = "Endpoint RDS MySQL (private, chi trong VPC)"
  value       = aws_db_instance.mysql.address
}

output "s3_bucket" {
  description = "Ten bucket S3 chua static asset"
  value       = aws_s3_bucket.assets.id
}
