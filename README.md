# web-hosting

Reusable Terraform module that creates a complete static site hosting stack on AWS with S3, CloudFront, ACM certificate, and Route53 DNS.

## What it creates

- ACM certificate with DNS validation via Route53
- S3 bucket with versioning, encryption (KMS or AES256), lifecycle rules, and CloudFront-only access
- CloudFront distribution with OAC, security headers, geo restrictions, and SPA error handling
- CloudFront response headers policy (HSTS, X-Frame-Options, XSS protection, etc.)
- Route53 A record aliased to the CloudFront distribution

## Usage

```hcl
module "web" {
  source = "git::https://github.com/domgiordano/web-hosting.git?ref=v1.0.0"

  app_name    = "myapp"
  domain_name = "myapp.com"
  zone_id     = data.aws_route53_zone.zone.zone_id
  tags        = { source = "terraform", app_name = "myapp" }

  # Optional: KMS encryption (default is AES256)
  kms_key_arn = aws_kms_alias.myapp.target_key_arn

  # Optional: WAF protection
  waf_acl_arn = module.waf_cloudfront.web_acl_arn
}
```

## Restricting access (Basic Auth)

Gate part of a site behind a single shared credential — e.g. keep the landing
page public but require a login for `/dashboards/*`:

```hcl
module "web" {
  source = "git::https://github.com/domgiordano/web-hosting.git?ref=v1.5.0"

  app_name    = "vest"
  domain_name = "example.com"
  zone_id     = data.aws_route53_zone.zone.zone_id

  enable_cache           = false          # drop-to-live: S3 uploads serve immediately
  enable_basic_auth      = true
  basic_auth_username    = var.dashboard_user
  basic_auth_password    = var.dashboard_password   # mark sensitive in your tfvars
  basic_auth_path_prefix = "/dashboards/"           # landing page stays public
}
```

> **Interim gate, not strong auth.** The `base64(user:pass)` token is embedded
> in the CloudFront Function source, which is visible in Terraform state and the
> AWS console. Use it to keep casual visitors out of a subtree; for real
> identity (per-user accounts, sensitive data) front it with Cognito or another
> IdP instead.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `app_name` | Application name for resource naming | `string` | — | yes |
| `domain_name` | Domain name for the site (e.g., myapp.com) | `string` | — | yes |
| `zone_id` | Route53 hosted zone ID for DNS records | `string` | — | yes |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |
| `kms_key_arn` | KMS key ARN for S3 encryption. Leave empty for AES256. | `string` | `""` | no |
| `force_destroy` | Allow bucket deletion even when non-empty | `bool` | `true` | no |
| `origin_path` | CloudFront origin path to serve from an S3 subdirectory | `string` | `""` | no |
| `spa_error_path` | Path returned for 403 errors (SPA routing). Empty to disable. | `string` | `"/index.html"` | no |
| `geo_restriction_locations` | Country codes for geo restriction whitelist. Empty for no restriction. | `list(string)` | `["US", "CA"]` | no |
| `enable_cache` | Enable CloudFront caching. When false, TTLs are set to 0. | `bool` | `true` | no |
| `default_ttl` | Default TTL for CloudFront cache (seconds) | `number` | `60` | no |
| `max_ttl` | Max TTL for CloudFront cache (seconds) | `number` | `60` | no |
| `enable_subroute_rewrite` | Attach a viewer-request function rewriting `/foo` and `/foo/` to `index.html`/`.html` (static-export deep routes). | `bool` | `false` | no |
| `subject_alternative_names` | Extra domains added to the ACM cert + CloudFront aliases (each gets a Route53 alias). | `list(string)` | `[]` | no |
| `canonical_host` | When set (with SANs), 301-redirects non-canonical hosts to this host via a viewer-request function. | `string` | `""` | no |
| `enable_basic_auth` | Attach HTTP Basic Auth (single shared credential) at viewer-request, gating paths under `basic_auth_path_prefix`. Interim gate only — see note below. | `bool` | `false` | no |
| `basic_auth_username` | Username for Basic Auth. Required when `enable_basic_auth` is true. | `string` | `""` | no |
| `basic_auth_password` | Password for Basic Auth (sensitive). Required when `enable_basic_auth` is true. | `string` | `""` | no |
| `basic_auth_path_prefix` | URI prefix that requires Basic Auth. `/` protects the whole site; `/dashboards/` gates one subtree. | `string` | `"/"` | no |
| `minimum_tls_version` | Minimum TLS version for CloudFront | `string` | `"TLSv1.2_2018"` | no |
| `waf_acl_arn` | WAF Web ACL ARN to associate with CloudFront. Leave empty to skip. | `string` | `""` | no |
| `retain_on_delete` | Disable distribution instead of deleting when destroying | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| `s3_bucket_id` | The S3 bucket ID |
| `s3_bucket_arn` | The S3 bucket ARN (for IAM policies) |
| `s3_bucket_regional_domain_name` | The S3 bucket regional domain name |
| `cloudfront_distribution_id` | The CloudFront distribution ID (for cache invalidation) |
| `cloudfront_distribution_arn` | The CloudFront distribution ARN (for KMS policies, etc.) |
| `cloudfront_domain_name` | The CloudFront distribution domain name |
| `certificate_arn` | The ACM certificate ARN (can be shared with other resources like API Gateway) |

## What stays outside the module

These are project-specific and should be defined in your project's Terraform:

- **KMS key** — kept outside to avoid circular dependencies (KMS policy references CloudFront ARN, CloudFront uses S3 which uses KMS)
- **WAF Web ACL** — use the [waf](https://github.com/domgiordano/waf) module and pass the ARN via `waf_acl_arn`
- **Route53 hosted zone** — the data source for your zone

## S3 Bucket Features

- **Versioning** enabled with lifecycle rules to auto-delete old versions
- **Encryption** with KMS or AES256 (configurable)
- **Public access blocked** — only CloudFront OAC can read objects
- **Lifecycle rules**: keeps latest 3 noncurrent versions, deletes versions older than 90 days

## Security Headers

The CloudFront response headers policy includes:
- `Strict-Transport-Security` (HSTS with preload, 1 year max-age)
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: SAMEORIGIN`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `X-XSS-Protection: 1; mode=block`

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.0 |
| AWS Provider | >= 4.0 |
