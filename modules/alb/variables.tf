variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "name_prefix" {
  type = string
}
