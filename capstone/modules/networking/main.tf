data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# We use the community VPC module for the actual Capstone to be production-ready.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.prefix}-vpc"
  cidr = var.vpc_cidr

  azs              = local.azs
  public_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  private_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 10)]
  database_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 20)]

  create_database_subnet_group = true

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  # tfsec:ignore:aws-ec2-no-public-ip-subnet
  map_public_ip_on_launch = true
}
