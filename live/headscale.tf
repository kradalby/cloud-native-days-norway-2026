resource "gigahost_server" "headscale" {
  hostname = "headscale"
  type     = "performance"
  size     = "2c-4gb-40gb"
  os       = "debian-13"
  timeouts = { create = "10m" } # a hung deploy fails fast; apply again to replace it
  ssh_keys = local.ssh_keys

  connection {
    host = self.ip
    user = "root"
  }

  provisioner "remote-exec" {
    inline = local.install_tailscale
  }
}

resource "gigahost_dns_record" "vpn_a" {
  zone_id = data.gigahost_dns_zone.demo.id
  name    = "vpn"
  type    = "A"
  value   = gigahost_server.headscale.ip
  ttl     = 60
}

resource "gigahost_dns_record" "vpn_aaaa" {
  zone_id = data.gigahost_dns_zone.demo.id
  name    = "vpn"
  type    = "AAAA"
  value   = gigahost_server.headscale.ipv6
  ttl     = 60
}
