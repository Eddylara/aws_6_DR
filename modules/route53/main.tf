terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_alb_dns
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 2
  request_interval  = 10

  tags = {
    Name = "primary-health-check"
  }
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = var.secondary_alb_dns
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 2
  request_interval  = 10

  tags = {
    Name = "secondary-health-check"
  }
}

resource "aws_cloudwatch_metric_alarm" "primary_health_check" {
  alarm_name          = "route53-primary-health-check-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Alerta cuando el health check primario de Route 53 deja de estar saludable"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]
  insufficient_data_actions = [var.sns_topic_arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }
}

resource "aws_cloudwatch_metric_alarm" "secondary_health_check" {
  alarm_name          = "route53-secondary-health-check-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Alerta cuando el health check secundario de Route 53 deja de estar saludable"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]
  insufficient_data_actions = [var.sns_topic_arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.secondary.id
  }
}

data "aws_route53_zone" "main" {
  name         = "eddylara.art"
  private_zone = false
}

resource "aws_route53_record" "primary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "ddr5-proyecto-6.eddylara.art"
  type    = "CNAME"
  ttl     = 60

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary"
  records         = [var.primary_alb_dns]
  health_check_id = aws_route53_health_check.primary.id
}

resource "aws_route53_record" "secondary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "ddr5-proyecto-6.eddylara.art"
  type    = "CNAME"
  ttl     = 60

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "secondary"
  records        = [var.secondary_alb_dns]
}