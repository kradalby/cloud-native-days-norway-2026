# The operator logs in to headscale with this OAuth client and mints keys for
# the proxies it starts (tag:k8s).
resource "tailscale_oauth_client" "k8s_operator" {
  description = "k8s operator"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s-operator"]
}

output "operator_client_id" {
  value = tailscale_oauth_client.k8s_operator.id
}

output "operator_client_secret" {
  value     = tailscale_oauth_client.k8s_operator.key
  sensitive = true
}
