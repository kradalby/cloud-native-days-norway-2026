# Every Debian VM runs this on first boot. The image ships without curl.
locals {
  install_tailscale = [
    "apt-get update && apt-get install -y curl",
    "curl -fsSL https://tailscale.com/install.sh | sh",
  ]
}
