#######################################
# Route53 DNS Records
#
# Primary record for var.domain_name + extra A-aliases for each SAN. All
# point at the same CloudFront distribution.
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

resource "aws_route53_record" "san" {
  for_each = toset(var.subject_alternative_names)

  zone_id = var.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = true
  }
}
