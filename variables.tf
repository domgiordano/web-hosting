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

variable "enable_subroute_rewrite" {
  description = "Attach a CloudFront Function that rewrites /foo and /foo/ to /foo/index.html. Required for static-export apps with deep routes (Next.js export, etc.) when the SPA error fallback would otherwise serve the home page for every URL."
  type        = bool
  default     = false
}

variable "subroute_style" {
  description = "How enable_subroute_rewrite resolves /foo: \"html\" rewrites to /foo.html (trailingSlash off), \"directory\" 301s to /foo/ (trailingSlash on, where only /foo/index.html exists)."
  type        = string
  default     = "html"

  validation {
    condition     = contains(["html", "directory"], var.subroute_style)
    error_message = "subroute_style must be \"html\" or \"directory\"."
  }
}

variable "subject_alternative_names" {
  description = "Additional domain names to include on the ACM cert and CloudFront aliases. Useful for IDN canonical/non-canonical pairs (e.g. punycode + ASCII fallback). Each entry also gets a Route53 A-record alias to the same distribution."
  type        = list(string)
  default     = []
}

variable "canonical_host" {
  description = <<-EOT
    Canonical hostname for redirects. When set (and subject_alternative_names is
    non-empty), attaches a CloudFront Function that 301-redirects any request whose
    Host header doesn't match this value to the same path on canonical_host. Use
    either var.domain_name or one of the SANs as the canonical.

    Composes with enable_subroute_rewrite: when both are enabled, a single
    viewer-request function handles canonical redirect first, then subroute
    rewrite. CloudFront only allows one viewer-request function per behavior, so
    we combine them in code.
  EOT
  type        = string
  default     = ""
}

variable "enable_basic_auth" {
  description = <<-EOT
    Attach HTTP Basic Auth (single shared credential) at the viewer-request
    stage. Gates only requests whose URI starts with var.basic_auth_path_prefix
    (default: the whole site). Composes with canonical_host and
    enable_subroute_rewrite in the same combined function — auth is checked
    first.

    WARNING: the base64(user:pass) token is embedded in the CloudFront Function
    source, which is visible in Terraform state and the AWS console. This is an
    interim shared-credential gate, NOT strong auth. Use a real identity
    provider (e.g. Cognito) for sensitive production access.
  EOT
  type        = bool
  default     = false
}

variable "basic_auth_username" {
  description = "Username for Basic Auth. Required when enable_basic_auth is true."
  type        = string
  default     = ""
}

variable "basic_auth_password" {
  description = "Password for Basic Auth. Required when enable_basic_auth is true. The base64(user:pass) token is embedded in the CloudFront Function source — interim gate only (see enable_basic_auth)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "basic_auth_path_prefix" {
  description = "Only requests whose URI starts with this prefix require Basic Auth. Default '/' protects the entire site. Example: '/dashboards/' to gate one subtree while keeping the rest public."
  type        = string
  default     = "/"
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
