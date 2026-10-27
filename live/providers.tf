provider "gigahost" {} # GIGAHOST_TOKEN from .envrc

# The stock Tailscale provider, pointed at headscale. The API key only exists
# once headscale runs, so it is minted live:
#   export TAILSCALE_API_KEY=$(ssh root@vpn.demo.headscale.no headscale apikeys create)
provider "tailscale" {
  base_url = "https://vpn.demo.headscale.no"
}
