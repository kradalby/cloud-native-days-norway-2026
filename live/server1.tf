resource "gigahost_server" "server1" {
  hostname = "server1"
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

resource "gigahost_dns_record" "server1" {
  zone_id = data.gigahost_dns_zone.demo.id
  name    = "server1"
  type    = "A"
  value   = gigahost_server.server1.ip
  ttl     = 60
}
