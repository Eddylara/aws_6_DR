output "source_bucket_id" {
  value = aws_s3_bucket.source.id
}

output "destination_bucket_id" {
  value = aws_s3_bucket.destination.id
}
