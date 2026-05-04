# Optional CloudFront Functions for the viewer-request stage.
#
# CloudFront only allows ONE viewer-request function per cache behavior, so
# when multiple behaviors are needed (canonical-host redirect + subroute
# rewrite) we generate a SINGLE combined function whose body branches on
# which features are enabled.
#
# If neither feature is enabled, no function is created and no association
# is attached.

locals {
  needs_viewer_request_function = var.enable_subroute_rewrite || var.canonical_host != ""

  # Combined function code. Order matters: canonical redirect runs first so
  # we send the 301 before doing any URI rewriting (rewrites would mutate
  # request.uri and waste cache entries on the wrong host).
  viewer_request_function_code = <<-EOF
    function handler(event) {
      var request = event.request;
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
          // No file extension and no trailing slash — try .html (Next.js
          // static-export style) before falling back to the SPA error path.
          request.uri = uri + '.html';
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
    var.canonical_host != "" ? "canonical-host redirect to ${var.canonical_host}" : "",
    var.enable_subroute_rewrite ? "subroute rewrite for static-export deep routes" : "",
  ])))
  publish = true
  code    = local.viewer_request_function_code
}
