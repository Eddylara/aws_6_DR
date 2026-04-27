terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.primary, aws.secondary]
    }
  }
}

resource "aws_db_subnet_group" "primary" {
  provider   = aws.primary
  name       = "db-subnet-primary"
  subnet_ids = var.primary_subnet_ids
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "db-subnet-secondary"
  subnet_ids = var.secondary_subnet_ids
}

resource "aws_security_group" "primary_rds_sg" {
  provider    = aws.primary
  name        = "primary-rds-sg"
  description = "RDS SG primary"
  vpc_id      = var.primary_vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "secondary_rds_sg" {
  provider    = aws.secondary
  name        = "secondary-rds-sg"
  description = "RDS SG secondary"
  vpc_id      = var.secondary_vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "primary_mysql" {
  provider               = aws.primary
  identifier             = "db-dr-primary"
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.primary_rds_sg.id]
  backup_retention_period = 1
  skip_final_snapshot    = true
  publicly_accessible    = true
}

resource "aws_db_instance" "secondary_read_replica" {
  provider               = aws.secondary
  identifier             = "db-dr-secondary-replica"
  instance_class         = "db.t3.micro"
  replicate_source_db    = aws_db_instance.primary_mysql.arn
  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [aws_security_group.secondary_rds_sg.id]
  publicly_accessible    = true
  skip_final_snapshot    = true

  depends_on = [aws_db_instance.primary_mysql]
}