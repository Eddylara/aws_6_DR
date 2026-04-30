output "zone_id" {
  value = data.aws_route53_zone.main.zone_id
}

output "app_dns" {
  value = aws_route53_record.primary.fqdn
}

output "primary_health_check_id" {
  value = aws_route53_health_check.primary.id
}

output "secondary_health_check_id" {
  value = aws_route53_health_check.secondary.id
}

output "primary_health_check_alarm_name" {
  value = aws_cloudwatch_metric_alarm.primary_health_check.alarm_name
}

output "secondary_health_check_alarm_name" {
  value = aws_cloudwatch_metric_alarm.secondary_health_check.alarm_name
}