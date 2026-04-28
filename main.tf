module "vpc_primary" {
  source = "./modules/vpc"

  providers = {
    aws = aws.primary
  }

  vpc_cidr        = var.vpc_cidr
  public_subnet_1 = var.public_subnet_1_cidr
  public_subnet_2 = var.public_subnet_2_cidr
  az_1            = "us-east-1a"
  az_2            = "us-east-1b"
  name_prefix     = "primary"
}

module "vpc_secondary" {
  source = "./modules/vpc"

  providers = {
    aws = aws.secondary
  }

  vpc_cidr        = var.vpc_cidr
  public_subnet_1 = var.public_subnet_1_cidr
  public_subnet_2 = var.public_subnet_2_cidr
  az_1            = "us-west-2a"
  az_2            = "us-west-2b"
  name_prefix     = "secondary"
}

module "alb_primary" {
  source = "./modules/alb"

  providers = {
    aws = aws.primary
  }

  vpc_id      = module.vpc_primary.vpc_id
  subnet_ids  = module.vpc_primary.subnet_ids
  name_prefix = "primary"
}

module "alb_secondary" {
  source = "./modules/alb"

  providers = {
    aws = aws.secondary
  }

  vpc_id      = module.vpc_secondary.vpc_id
  subnet_ids  = module.vpc_secondary.subnet_ids
  name_prefix = "secondary"
}

module "ec2_asg_primary" {
  source = "./modules/ec2_asg"

  providers = {
    aws = aws.primary
  }

  vpc_id             = module.vpc_primary.vpc_id
  subnet_ids         = module.vpc_primary.subnet_ids
  target_group_arn   = module.alb_primary.target_group_arn
  alb_security_group = module.alb_primary.alb_security_group_id
  min_size           = 2
  desired_capacity   = 2
  max_size           = 4
  name_prefix        = "primary"
  db_host            = module.rds.primary_endpoint
  db_name            = var.db_name
  db_user            = var.db_username
  db_password        = var.db_password
}

module "ec2_asg_secondary" {
  source = "./modules/ec2_asg"

  providers = {
    aws = aws.secondary
  }

  vpc_id             = module.vpc_secondary.vpc_id
  subnet_ids         = module.vpc_secondary.subnet_ids
  target_group_arn   = module.alb_secondary.target_group_arn
  alb_security_group = module.alb_secondary.alb_security_group_id
  min_size           = 0
  desired_capacity   = 0
  max_size           = 4
  name_prefix        = "secondary"
  db_host            = module.rds.secondary_replica_endpoint
  db_name            = var.db_name
  db_user            = var.db_username
  db_password        = var.db_password
}

module "rds" {
  source = "./modules/rds"

  providers = {
    aws.primary   = aws.primary
    aws.secondary = aws.secondary
  }

  primary_subnet_ids   = module.vpc_primary.subnet_ids
  secondary_subnet_ids = module.vpc_secondary.subnet_ids
  primary_vpc_id       = module.vpc_primary.vpc_id
  secondary_vpc_id     = module.vpc_secondary.vpc_id
  db_name              = var.db_name
  db_username          = var.db_username
  db_password          = var.db_password
}

module "s3" {
  source = "./modules/s3"

  providers = {
    aws.primary   = aws.primary
    aws.secondary = aws.secondary
  }

  source_bucket_name      = var.source_bucket_name
  destination_bucket_name = var.destination_bucket_name
}

module "dynamodb" {
  source = "./modules/dynamodb"

  providers = {
    aws = aws.primary
  }

  table_name       = var.dynamodb_table_name
  secondary_region = var.secondary_region
}

module "route53" {
  source = "./modules/route53"

  primary_alb_dns   = module.alb_primary.alb_dns_name
  secondary_alb_dns = module.alb_secondary.alb_dns_name
}


module "cloudwatch" {
  source = "./modules/cloudwatch"

  providers = {
    aws.secondary = aws.secondary
  }

  primary_alb_arn_suffix   = module.alb_primary.alb_arn_suffix
  primary_tg_arn_suffix    = module.alb_primary.target_group_arn_suffix
  secondary_alb_arn_suffix = module.alb_secondary.alb_arn_suffix
  secondary_tg_arn_suffix  = module.alb_secondary.target_group_arn_suffix
}