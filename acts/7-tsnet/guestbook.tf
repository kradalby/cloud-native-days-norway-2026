# For guestbook-tsnet on server1: its own node, apart from server1's.
resource "tailscale_tailnet_key" "guestbook" {
  tags          = ["tag:guestbook"]
  reusable      = false
  preauthorized = true
  expiry        = 3600
  description   = "guestbook-tsnet"
}

output "guestbook_key" {
  value     = tailscale_tailnet_key.guestbook.key
  sensitive = true
}
