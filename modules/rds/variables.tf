variable "primary_subnet_ids" {
  type = list(string)
}

variable "secondary_subnet_ids" {
  type = list(string)
}

variable "primary_vpc_id" {
  type = string
}

variable "secondary_vpc_id" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}
