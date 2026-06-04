#sinh ssh key bang tls provider
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  key_name   = "${var.project}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "ssh_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/${var.project}-key.pem"
  file_permission = "0400"
}

data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

resource "aws_security_group" "ec2" {
  name        = "${var.project}-ec2-sg"
  description = "EC2 security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port - CHI tu ALB"
    from_port       = 30080
    to_port         = 30080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
    description = "SSH only IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
    description = "minikube apiserver - chi IP ban"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  egress {
    description = "Ra moi noi (keo image, package)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-ec2-sg" }
}

# Elastic IP - IP public CO DINH (auto IP doi khi stop/start -> vo cert+kubeconfig)
resource "aws_eip" "web" {
  domain = "vpc"
  tags   = { Name = "${var.project}-eip" }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023_arm.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = aws_key_pair.deployer.key_name

  # inject EIP vao script -> minikube cert + kubeconfig dung IP co dinh
  user_data                   = templatefile("${path.module}/user_data.sh.tpl", { eip = aws_eip.web.public_ip })
  user_data_replace_on_change = true # doi user_data -> tao instance moi (sach), khong stop/start in-place

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "${var.project}-ec2" }
}

# Gan EIP vao instance
resource "aws_eip_association" "web" {
  instance_id   = aws_instance.web.id
  allocation_id = aws_eip.web.id
}
