resource "aws_sns_topic" "alerts" {
  name = "dr-alerts"
}

resource "aws_cloudwatch_metric_alarm" "primary_health" {
  alarm_name          = "primary-alb-unhealthy-hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Región primaria sin hosts saludables"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.primary_alb_arn_suffix
    TargetGroup  = var.primary_tg_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "secondary_health" {
  alarm_name          = "secondary-alb-unhealthy-hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Región secundaria sin hosts saludables"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.secondary_alb_arn_suffix
    TargetGroup  = var.secondary_tg_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_primary_cpu" {
  alarm_name          = "rds-primary-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU de RDS primaria mayor al 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = "db-dr-primary"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_replica_lag" {
  provider            = aws.secondary
  alarm_name          = "rds-replica-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Lag de réplica RDS mayor a 30 segundos"

  dimensions = {
    DBInstanceIdentifier = "db-dr-secondary-replica"
  }
}