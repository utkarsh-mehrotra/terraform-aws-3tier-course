variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "capstone"
}

variable "domain_name" {
  type    = string
  default = "example.com"
}

variable "db_password" {
  type      = string
  sensitive = true
}
