provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

locals {
  prefix = "${var.project_name}-${var.environment}"
}

module "networking" {
  source = "./modules/networking"

  prefix     = local.prefix
  vpc_cidr   = "10.0.0.0/16"
  aws_region = var.aws_region
}

module "security" {
  source = "./modules/security"

  prefix = local.prefix
  vpc_id = module.networking.vpc_id
}

module "data" {
  source = "./modules/data"

  prefix                  = local.prefix
  vpc_id                  = module.networking.vpc_id
  db_subnet_group_name    = module.networking.db_subnet_group_name
  rds_security_group_id   = module.security.rds_sg_id
  redis_security_group_id = module.security.redis_sg_id
  db_password             = var.db_password
}

module "compute" {
  source = "./modules/compute"

  prefix                      = local.prefix
  vpc_id                      = module.networking.vpc_id
  public_subnets              = module.networking.public_subnets
  private_app_subnets         = module.networking.private_app_subnets
  alb_security_group_id       = module.security.alb_sg_id
  ecs_security_group_id       = module.security.ecs_sg_id
  ecs_task_execution_role_arn = module.security.ecs_execution_role_arn
  ecs_task_role_arn           = module.security.ecs_task_role_arn
  domain_name                 = var.domain_name
  db_secret_arn               = module.security.db_secret_arn
}

module "observability" {
  source = "./modules/observability"

  prefix         = local.prefix
  alb_arn_suffix = module.compute.alb_arn_suffix
}
