#######################################
# ACM Certificate
#######################################

resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  tags              = merge(var.tags, { "name" = "${var.app_name}-certificate" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

#######################################
# S3 Bucket
#######################################

resource "aws_s3_bucket" "site" {
  bucket        = var.domain_name
  force_destroy = var.force_destroy
  tags          = merge(var.tags, { "name" = var.domain_name })
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    id = "delete-older-than-latest-3-versions"
    noncurrent_version_expiration {
      newer_noncurrent_versions = 3
      noncurrent_days           = 1
    }
    status = "Enabled"
  }

  rule {
    id = "delete-old-versions-after-90-days"
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontAccess"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
          }
        }
      }
    ]
  })
}

#######################################
# CloudFront
#######################################

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "oac-for-${var.app_name}"
  description                       = "OAC for S3 bucket ${var.app_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "${var.app_name}-origin"
    origin_path              = var.origin_path
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  web_acl_id          = var.waf_acl_arn != "" ? var.waf_acl_arn : null
  aliases             = [var.domain_name]
  retain_on_delete    = var.retain_on_delete
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  dynamic "custom_error_response" {
    for_each = var.spa_error_path != "" ? [1] : []
    content {
      error_code         = 403
      response_code      = 200
      response_page_path = var.spa_error_path
    }
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "${var.app_name}-origin"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = var.enable_cache ? var.default_ttl : 0
    max_ttl                = var.enable_cache ? var.max_ttl : 0
    viewer_protocol_policy = "redirect-to-https"
  }

  dynamic "restrictions" {
    for_each = length(var.geo_restriction_locations) > 0 ? [1] : []
    content {
      geo_restriction {
        restriction_type = "whitelist"
        locations        = var.geo_restriction_locations
      }
    }
  }

  dynamic "restrictions" {
    for_each = length(var.geo_restriction_locations) == 0 ? [1] : []
    content {
      geo_restriction {
        restriction_type = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = aws_acm_certificate.cert.arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = var.minimum_tls_version
  }

  depends_on = [aws_acm_certificate_validation.cert]

  tags = merge(var.tags, { "name" = "${var.app_name}-cloudfront" })
}

resource "aws_cloudfront_response_headers_policy" "site" {
  name = "security-headers-policy-for-${var.app_name}"

  security_headers_config {
    content_type_options {
      override = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
      preload                    = true
    }
    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    xss_protection {
      mode_block = true
      override   = true
      protection = true
    }
  }
}

#######################################
# Route53 DNS Record
#######################################

resource "aws_route53_record" "site" {
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = true
  }
}
