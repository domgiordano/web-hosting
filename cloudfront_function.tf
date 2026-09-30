# Optional CloudFront Functions for the viewer-request stage.
#
# CloudFront only allows ONE viewer-request function per cache behavior, so
# when multiple features are needed (basic auth + canonical-host redirect +
# subroute rewrite) we generate a SINGLE combined function whose body branches
# on which features are enabled.
#
# If neither feature is enabled, no function is created and no association
# is attached.

locals {
  needs_viewer_request_function = var.enable_subroute_rewrite || var.canonical_host != "" || var.enable_basic_auth

  # base64(user:pass) embedded in the function source when basic auth is on.
  # Visible in Terraform state and the AWS console — this is an interim
  # shared-credential gate, NOT strong auth. Replace with a real IdP (Cognito)
  # for sensitive production access.
  basic_auth_token = base64encode("${var.basic_auth_username}:${var.basic_auth_password}")

  # Combined function code. Order matters:
  #   1. basic auth — challenge unauthorized requests before doing any work
  #   2. canonical  — 301 to the canonical host before URI rewriting (rewrites
  #      would mutate request.uri and waste cache entries on the wrong host)
  #   3. rewrite    — normalize deep routes to .html / index.html
  viewer_request_function_code = <<-EOF
    function handler(event) {
      var request = event.request;
      ${var.enable_basic_auth ? <<-BASICAUTH
        var authUri = request.uri;
        if (authUri.startsWith('${var.basic_auth_path_prefix}')) {
          var authHeader = request.headers.authorization;
          var expected = 'Basic ${local.basic_auth_token}';
          if (!authHeader || authHeader.value !== expected) {
            return {
              statusCode: 401,
              statusDescription: 'Unauthorized',
              headers: {
                'www-authenticate': { value: 'Basic realm="Restricted"' }
              }
            };
          }
        }
BASICAUTH
  : ""}
      ${var.canonical_host != "" ? <<-CANONICAL
        var canonical = '${var.canonical_host}';
        var hostHeader = request.headers.host;
        var host = hostHeader && hostHeader.value;
        if (host && host !== canonical) {
          var qsParts = [];
          for (var k in request.querystring) {
            qsParts.push(k + '=' + request.querystring[k].value);
          }
          var location = 'https://' + canonical + request.uri + (qsParts.length ? '?' + qsParts.join('&') : '');
          return {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: { location: { value: location } }
          };
        }
CANONICAL
  : ""}
      ${var.enable_subroute_rewrite ? <<-REWRITE
        var uri = request.uri;
        if (uri !== '/' && uri.endsWith('/')) {
          request.uri = uri + 'index.html';
        } else if (uri !== '/' && !uri.includes('.')) {
          ${var.subroute_style == "directory" ? <<-DIR
          // trailingSlash builds only have /foo/index.html, so send /foo to
          // /foo/ rather than serving the SPA fallback (the home page).
          var qs = Object.keys(request.querystring).map(function (k) {
            var v = request.querystring[k];
            return v.multiValue
              ? v.multiValue.map(function (m) { return k + '=' + m.value; }).join('&')
              : k + '=' + v.value;
          }).join('&');
          return {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: { location: { value: uri + '/' + (qs ? '?' + qs : '') } }
          };
DIR
  : <<-HTML
          // No file extension and no trailing slash — try .html (Next.js
          // static-export style) before falling back to the SPA error path.
          request.uri = uri + '.html';
HTML
}
        }
REWRITE
: ""}
      return request;
    }
  EOF
}

resource "aws_cloudfront_function" "viewer_request" {
  count   = local.needs_viewer_request_function ? 1 : 0
  name    = "${var.app_name}-viewer-request"
  runtime = "cloudfront-js-2.0"
  comment = trimspace(join(" + ", compact([
    var.enable_basic_auth ? "basic auth on ${var.basic_auth_path_prefix}" : "",
    var.canonical_host != "" ? "canonical-host redirect to ${var.canonical_host}" : "",
    var.enable_subroute_rewrite ? "subroute rewrite for static-export deep routes" : "",
  ])))
  publish = true
  code    = local.viewer_request_function_code

  lifecycle {
    precondition {
      condition     = !var.enable_basic_auth || (var.basic_auth_username != "" && var.basic_auth_password != "")
      error_message = "enable_basic_auth is true but basic_auth_username and/or basic_auth_password are empty."
    }
  }
}
