############################
# Core
############################

variable "app_name" {
  description = "Application name, used for naming resources"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the site (e.g., myapp.com)"
  type        = string
}

variable "zone_id" {
  description = "Route53 hosted zone ID for DNS records"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

############################
# S3
############################

variable "kms_key_arn" {
  description = "KMS key ARN for S3 bucket encryption. Leave empty for AES256."
  type        = string
  default     = ""
}

variable "force_destroy" {
  description = "Allow bucket deletion even when non-empty"
  type        = bool
  default     = true
}

############################
# CloudFront
############################

variable "origin_path" {
  description = "Optional CloudFront origin path to request content from a directory in S3"
  type        = string
  default     = ""
}

variable "spa_error_path" {
  description = "Path to return for 403 errors (SPA routing). Set empty to disable."
  type        = string
  default     = "/index.html"
}

variable "geo_restriction_locations" {
  description = "List of country codes for geo restriction whitelist. Empty list for no restriction."
  type        = list(string)
  default     = ["US", "CA"]
}

variable "enable_cache" {
  description = "Enable CloudFront caching. When false, default_ttl and max_ttl are 0."
  type        = bool
  default     = true
}

variable "default_ttl" {
  description = "Default TTL for CloudFront cache (seconds)"
  type        = number
  default     = 60
}

variable "max_ttl" {
  description = "Max TTL for CloudFront cache (seconds)"
  type        = number
  default     = 60
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for CloudFront"
  type        = string
  default     = "TLSv1.2_2018"
}

variable "waf_acl_arn" {
  description = "WAF Web ACL ARN to associate with CloudFront. Leave empty to skip."
  type        = string
  default     = ""
}

variable "retain_on_delete" {
  description = "Disable distribution instead of deleting when destroying"
  type        = bool
  default     = false
}
