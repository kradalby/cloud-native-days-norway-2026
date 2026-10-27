resource "tailscale_tailnet_key" "rpi4" {
  tags          = ["tag:rpi"]
  reusable      = false
  preauthorized = true
  expiry        = 3600
  description   = "rpi4"
}

output "rpi4_key" {
  value     = tailscale_tailnet_key.rpi4.key
  sensitive = true
}
