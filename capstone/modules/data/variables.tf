variable "prefix" { type = string }
variable "vpc_id" { type = string }
variable "db_subnet_group_name" { type = string }
variable "rds_security_group_id" { type = string }
variable "redis_security_group_id" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
