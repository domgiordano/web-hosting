output "s3_bucket_id" {
  description = "The S3 bucket ID"
  value       = aws_s3_bucket.site.id
}

output "s3_bucket_arn" {
  description = "The S3 bucket ARN"
  value       = aws_s3_bucket.site.arn
}

output "s3_bucket_regional_domain_name" {
  description = "The S3 bucket regional domain name"
  value       = aws_s3_bucket.site.bucket_regional_domain_name
}

output "cloudfront_distribution_id" {
  description = "The CloudFront distribution ID"
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_distribution_arn" {
  description = "The CloudFront distribution ARN (for KMS policies, etc.)"
  value       = aws_cloudfront_distribution.site.arn
}

output "cloudfront_domain_name" {
  description = "The CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.site.domain_name
}

output "certificate_arn" {
  description = "The ACM certificate ARN"
  value       = aws_acm_certificate.cert.arn
}
