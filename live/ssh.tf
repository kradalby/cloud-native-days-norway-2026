# Literal, not file(): each machine running tofu has its own key.
resource "gigahost_account_ssh_key" "kradalby" {
  name       = "kradalby"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBV4ZjlUvRDs70qHD/Ldi6OTkFpDEFgfbXbqSnaL2Qup\n"
}

resource "gigahost_account_ssh_key" "kradalby_dev" {
  name       = "kradalby-dev"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJmukT03vff7EvEQb57NYPvM4TgCVLYcRq4SxE+YOSGx kradalby@dev\n"
}

locals {
  ssh_keys = [gigahost_account_ssh_key.kradalby.id, gigahost_account_ssh_key.kradalby_dev.id]
}
