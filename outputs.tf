output "primary_alb_dns" {
  value = module.alb_primary.alb_dns_name
}

output "secondary_alb_dns" {
  value = module.alb_secondary.alb_dns_name
}

output "rds_primary_endpoint" {
  value = module.rds.primary_endpoint
}

output "rds_secondary_replica_endpoint" {
  value = module.rds.secondary_replica_endpoint
}

output "s3_source_bucket" {
  value = module.s3.source_bucket_id
}

output "s3_destination_bucket" {
  value = module.s3.destination_bucket_id
}

output "dynamodb_global_table" {
  value = module.dynamodb.table_name
}

output "app_dns" {
  value = module.route53.app_dns
}

output "primary_health_check_id" {
  value = module.route53.primary_health_check_id
}

output "secondary_health_check_id" {
  value = module.route53.secondary_health_check_id
}


output "sns_alerts_topic" {
  value = module.cloudwatch.sns_topic_arn
}