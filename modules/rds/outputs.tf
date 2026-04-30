output "primary_endpoint" {
  value = aws_db_instance.primary_mysql.address
}

output "secondary_replica_endpoint" {
  value = aws_db_instance.secondary_read_replica.address
}

output "primary_db_identifier" {
  value = aws_db_instance.primary_mysql.identifier
}

output "secondary_replica_identifier" {
  value = aws_db_instance.secondary_read_replica.identifier
}
