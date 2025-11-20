########################################
# Provider
########################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

########################################
# VPC + Subnets
########################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "wp-vpc"
  }
}

# Public subnet for EC2 (WordPress)
resource "aws_subnet" "public1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "wp-public-1a"
  }
}

# Private subnets for RDS
resource "aws_subnet" "private1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "wp-private-1a"
  }
}

resource "aws_subnet" "private1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "wp-private-1b"
  }
}

########################################
# Internet access for public subnet
########################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "wp-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "wp-public-rt"
  }
}

resource "aws_route_table_association" "public1a_assoc" {
  subnet_id      = aws_subnet.public1a.id
  route_table_id = aws_route_table.public.id
}

########################################
# Security Groups
########################################

# EC2 (WordPress) security group
resource "aws_security_group" "wp_ec2_sg" {
  name        = "wp-ec2-sg"
  description = "Allow HTTP and SSH from internet"
  vpc_id      = aws_vpc.main.id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH (lab only – in real life restrict to your IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wp-ec2-sg"
  }
}

# RDS security group – only allow from EC2 SG on 3306
resource "aws_security_group" "wp_rds_sg" {
  name        = "wp-rds-sg"
  description = "Allow MySQL from WordPress EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wp_ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wp-rds-sg"
  }
}

########################################
# RDS: DB Subnet Group + Instance
########################################

resource "aws_db_subnet_group" "wp" {
  name       = "wp-db-subnets"
  subnet_ids = [
    aws_subnet.private1a.id,
    aws_subnet.private1b.id
  ]

  tags = {
    Name = "wp-db-subnet-group"
  }
}

resource "aws_db_instance" "wp" {
  identifier            = "wp-rds-instance"
  engine                = "mysql"
  engine_version        = "8.0"
  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  username = "wpadmin"              # lab only
  password = "ChangeMeStrong123!"   # lab only
  db_name  = "wordpressdb"

  db_subnet_group_name    = aws_db_subnet_group.wp.name
  vpc_security_group_ids  = [aws_security_group.wp_rds_sg.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  storage_encrypted       = true
  backup_retention_period = 0

  tags = {
    Name    = "wp-rds-mysql"
    Project = "wp-simple-demo"
  }
}

########################################
# EC2: WordPress server
########################################

resource "aws_instance" "wp_server" {
  ami           = "ami-0c02fb55956c7d316"  # Amazon Linux 2 in us-east-1
  instance_type = "t3.micro"

  subnet_id              = aws_subnet.public1a.id
  vpc_security_group_ids = [aws_security_group.wp_ec2_sg.id]

  associate_public_ip_address = true

  # Use an EXISTING key pair name from your AWS account
  key_name = "wp-key"

  user_data = <<-EOF
    #!/bin/bash
    yum update -y

    # Install Apache + PHP
    amazon-linux-extras install -y php8.0
    yum install -y httpd wget tar

    systemctl enable httpd
    systemctl start httpd

    cd /var/www/html

    # Download and extract WordPress
    wget https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz
    mv wordpress/* .
    rm -rf wordpress latest.tar.gz

    cp wp-config-sample.php wp-config.php

    # Configure WordPress to use RDS
    sed -i "s/database_name_here/wordpressdb/" wp-config.php
    sed -i "s/username_here/wpadmin/" wp-config.php
    sed -i "s/password_here/ChangeMeStrong123!/" wp-config.php
    sed -i "s/localhost/${aws_db_instance.wp.address}/" wp-config.php

    chown -R apache:apache /var/www/html
    chmod -R 755 /var/www/html
  EOF

  tags = {
    Name = "wp-ec2-server"
  }
}

########################################
# Outputs
########################################

output "wordpress_url" {
  description = "Open this in your browser"
  value       = "http://${aws_instance.wp_server.public_ip}"
}

output "rds_endpoint" {
  value = aws_db_instance.wp.address
}
