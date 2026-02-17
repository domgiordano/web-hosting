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
