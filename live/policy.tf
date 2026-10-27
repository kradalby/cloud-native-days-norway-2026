# Needs `policy.mode: database` in headscale's config. Must land before any
# key act: the API key has no user, so every key it mints is tagged.
resource "tailscale_acl" "policy" {
  acl                        = file("${path.module}/policy.hujson")
  overwrite_existing_content = true
}
