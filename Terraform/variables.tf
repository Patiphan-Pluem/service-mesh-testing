variable "aws_region" {
    description = "AWS region"
    default = "ap-southeast-1"
}

variable "k3s-project_az" { 
    default = "ap-southeast-1a" 
}

variable "project_name" {
    default = "service-mesh-k3s-project"
}