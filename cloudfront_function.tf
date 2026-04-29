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
