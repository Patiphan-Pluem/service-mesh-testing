terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }
}

provider "aws" {
    region = var.aws_region
}

# --- VPC ---
resource "aws_vpc" "k3s_server_vpc" {
    cidr_block = "172.16.0.0/16"
    enable_dns_hostnames = true
    tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "k3s_server_igw" {
    vpc_id = aws_vpc.k3s_server_vpc.id
    tags = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "k3s_server_rt" {
    vpc_id = aws_vpc.k3s_server_vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.k3s_server_igw.id
    }
    tags = { Name = "k3s_server-public-rt" }
}

resource "aws_subnet" "k3s_server_subnet" {
    vpc_id = aws_vpc.k3s_server_vpc.id
    cidr_block = "172.16.1.0/24"
    availability_zone = var.k3s-project_az
    map_public_ip_on_launch = true
    tags = { Name = "k3s-project-subnet-1a" }
}

resource "aws_route_table_association" "k3s_server_assoc" {
    subnet_id = aws_subnet.k3s_server_subnet.id
    route_table_id = aws_route_table.k3s_server_rt.id
}

# --- Security Group ---
resource "aws_security_group" "k3s_server_sg" {
    vpc_id = aws_vpc.k3s_server_vpc.id
    name = "${var.project_name}-sg"
    
    dynamic "ingress" {
    for_each = [
      { port = 22,    proto = "tcp",  desc = "SSH" },
      { port = 80,    proto = "tcp",  desc = "HTTP" },
      { port = 443,   proto = "tcp",  desc = "HTTPS" },
      { port = 6443,  proto = "tcp",  desc = "K8s API Server" },
      { port = 10250, proto = "tcp",  desc = "Kubelet API" },
    ]
    content {
      description      = ingress.value.desc
      from_port        = ingress.value.port
      to_port          = ingress.value.port
      protocol         = ingress.value.proto
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
        }
    }

    ingress {
        description = "Allow all ICMP"
        from_port   = -1
        to_port     = -1
        protocol    = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1" 
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = { Name = "k3s_server-sg" }
}

# --- Key Pair ---
resource "tls_private_key" "k3s_server_pk" { 
    algorithm = "ED25519" 
}

resource "aws_key_pair" "k3s_server_key" {
    key_name = "${var.project_name}-key"
    public_key = tls_private_key.k3s_server_pk.public_key_openssh
}

resource "local_file" "private_key_pem" {
  content         = tls_private_key.k3s_server_pk.private_key_pem
  filename        = "${path.module}/k3s-key.pem"
  file_permission = "0400" 
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners = ["099720109477"]
    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] 
    }
}

resource "aws_instance" "k3s_server" {
    ami = data.aws_ami.ubuntu.id
    instance_type = "t3a.xlarge"  
    subnet_id = aws_subnet.k3s_server_subnet.id
    vpc_security_group_ids = [aws_security_group.k3s_server_sg.id]
    key_name = aws_key_pair.k3s_server_key.key_name

    root_block_device {
        volume_size = 50 
        volume_type = "gp3"
        delete_on_termination = true
    }

    instance_market_options {
    market_type = "spot"
    spot_options {
      max_price = "0.12" 
      spot_instance_type = "persistent" 
      instance_interruption_behavior = "stop"
        }
    }

    source_dest_check = false
    user_data = <<-EOF
              #!/bin/bash
              apt-get update
              EOF
    lifecycle {
        ignore_changes = [ami]
    }
    tags = { Name = "k3s_server" }
}

