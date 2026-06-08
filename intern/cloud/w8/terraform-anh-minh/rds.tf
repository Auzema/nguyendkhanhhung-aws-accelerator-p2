# Subnet group: RDS doi >=2 subnet o >=2 AZ -> dung 2 private subnet
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnet"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "${var.project}-db-subnet" }
}

# SG cua RDS: chi mo 3306 TU SG cua EC2. Internet khong cham toi.
resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "RDS MySQL 3306 chi tu EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL 3306 chi tu EC2 SG"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-rds-sg" }
}

resource "aws_db_instance" "mysql" {
  identifier     = "${var.project}-mysql"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = "appdb"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # KHONG co public IP -> chi trong VPC
  multi_az               = false # single-AZ cho re

  skip_final_snapshot = true # destroy nhanh, khong tao snapshot cuoi

  # RDS tao/xoa lau -> noi rong timeout cho chac (default 40m, set 60m)
  timeouts {
    create = "60m"
    delete = "60m"
    update = "60m"
  }
}
