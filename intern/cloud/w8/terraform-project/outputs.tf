output "alb_url" {
  description = "URL ALB - mo browser kiem tra app (bang chung nop bai)"
  value       = "http://${aws_lb.alb.dns_name}"
}

output "ec2_public_ip" {
  description = "Elastic IP cua EC2 (co dinh) - SSH + apiserver"
  value       = aws_eip.web.public_ip
}

output "ssh_command" {
  description = "Lenh SSH vao EC2"
  value       = "ssh -i ${path.module}/${var.project}-key.pem ec2-user@${aws_eip.web.public_ip}"
}
