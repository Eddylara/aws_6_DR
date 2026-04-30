variable "sns_topic_arn" {
  type = string
}

variable "primary_health_alarm_name" {
  type = string
}

variable "secondary_region" {
  type = string
}

variable "secondary_asg_name" {
  type = string
}

variable "secondary_rds_identifier" {
  type = string
}

variable "desired_capacity" {
  type    = number
  default = 2
}
