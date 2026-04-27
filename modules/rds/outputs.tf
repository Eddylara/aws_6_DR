output "primary_endpoint" {
  value = aws_db_instance.primary_mysql.address
}

output "secondary_replica_endpoint" {
  value = aws_db_instance.secondary_read_replica.address
}
