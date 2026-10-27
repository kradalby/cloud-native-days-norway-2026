terraform {
  required_version = ">= 1.10"

  required_providers {
    gigahost = {
      source  = "kradalby/gigahost"
      version = "~> 0.0.1"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.29"
    }
  }
}
