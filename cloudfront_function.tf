# Optional: rewrite subroute requests like /foo or /foo/ to /foo/index.html so
# Next.js (or similar) static-export deep routes resolve to the right HTML
# instead of falling through to the SPA error page.

resource "aws_cloudfront_function" "subroute_rewrite" {
  count   = var.enable_subroute_rewrite ? 1 : 0
  name    = "${var.app_name}-subroute-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite /foo and /foo/ to /foo/index.html for static-export deep routes"
  publish = true
  code    = <<-EOF
    function handler(event) {
      var request = event.request;
      var uri = request.uri;
      // Append index.html for paths ending with '/'
      if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
      } else if (!uri.includes('.')) {
        // No file extension — assume directory, append /index.html
        request.uri = uri + '/index.html';
      }
      return request;
    }
  EOF
}

# Optional: 301-redirect any request whose Host header doesn't match
# var.canonical_host to the same path on the canonical host. Used to enforce
# IDN canonical (e.g. xomappétit.xomware.com) over an ASCII fallback host
# (xomappetit.xomware.com).

resource "aws_cloudfront_function" "canonical_redirect" {
  count   = var.canonical_host != "" ? 1 : 0
  name    = "${var.app_name}-canonical-redirect"
  runtime = "cloudfront-js-2.0"
  comment = "301 redirect non-canonical hosts to ${var.canonical_host}"
  publish = true
  code    = <<-EOF
    function handler(event) {
      var request = event.request;
      var canonical = '${var.canonical_host}';
      var hostHeader = request.headers.host;
      var host = hostHeader && hostHeader.value;
      if (!host || host === canonical) {
        return request;
      }
      var qsParts = [];
      for (var k in request.querystring) {
        qsParts.push(k + '=' + request.querystring[k].value);
      }
      var location = 'https://' + canonical + request.uri + (qsParts.length ? '?' + qsParts.join('&') : '');
      return {
        statusCode: 301,
        statusDescription: 'Moved Permanently',
        headers: {
          location: { value: location }
        }
      };
    }
  EOF
}
