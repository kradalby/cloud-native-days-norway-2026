# For tailscale/github-action: mints its own tag:ci keys per run.
resource "tailscale_oauth_client" "github" {
  description = "github actions"
  scopes      = ["auth_keys"]
  tags        = ["tag:ci"]
}

output "github_oauth_client_id" {
  value = tailscale_oauth_client.github.id
}

output "github_oauth_client_secret" {
  value     = tailscale_oauth_client.github.key
  sensitive = true
}
