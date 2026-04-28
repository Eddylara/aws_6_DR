output "zone_id" {
  value = aws_route53_zone.main.zone_id
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