# Gigahost boots Debian, nixos-anywhere replaces it with NixOS from acts/4-k3s/nixos.
# Slow: apply before going on stage. No tailnet key: act 4 joins the nodes
# (acts/4-k3s/k3s-join.tf).
resource "gigahost_server" "k3s" {
  for_each = toset(["k3s1", "k3s2", "k3s3"])

  hostname = each.key
  type     = "performance"
  size     = "2c-4gb-40gb"
  os       = "debian-13"
  timeouts = { create = "10m" } # a hung deploy fails fast; apply again to replace it
  ssh_keys = local.ssh_keys
}

resource "gigahost_dns_record" "k3s" {
  for_each = gigahost_server.k3s

  zone_id = data.gigahost_dns_zone.demo.id
  name    = each.key
  type    = "A"
  value   = each.value.ip
  ttl     = 60
}

# Lets the nodes join each other once k3s.nix is on. On disk from the
# install, so turning on k3s needs no new secret.
resource "random_password" "k3s_token" {
  length  = 32
  special = false
}

resource "local_sensitive_file" "k3s_token" {
  filename = ".terraform/k3s-token"
  content  = random_password.k3s_token.result
}

module "nixos" {
  source   = "github.com/nix-community/nixos-anywhere//terraform/all-in-one?ref=1.13.0"
  for_each = gigahost_server.k3s

  nixos_system_attr      = "path:${abspath("../acts/4-k3s/nixos")}#nixosConfigurations.k3s.config.system.build.toplevel"
  nixos_partitioner_attr = "path:${abspath("../acts/4-k3s/nixos")}#nixosConfigurations.k3s.config.system.build.diskoScript"
  target_host            = each.value.ip
  instance_id            = each.value.id

  special_args = {
    hostName = each.key
    host = {
      sshKeys     = [gigahost_account_ssh_key.kradalby.public_key, gigahost_account_ssh_key.kradalby_dev.public_key]
      ipv4        = each.value.ip
      ipv4Gateway = cidrhost("${each.value.ip}/24", 1)
      ipv6        = each.value.ipv6
      ipv6Gateway = cidrhost("${each.value.ipv6}/118", 1)
    }
  }

  extra_files_script = abspath("../acts/4-k3s/nixos/extra-files.sh")
  extra_environment = {
    K3S_TOKEN_FILE = abspath(local_sensitive_file.k3s_token.filename)
  }
}
