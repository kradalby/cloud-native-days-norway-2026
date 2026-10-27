# Made before the talk: a Gigahost VM takes minutes, the join on stage seconds.
# No SSH key: tofu logs in with the root password, we get in with
# Tailscale SSH.
resource "gigahost_server" "server2" {
  hostname = "server2"
  type     = "performance"
  size     = "2c-4gb-40gb"
  os       = "debian-13"
  timeouts = { create = "10m" } # a hung deploy fails fast; apply again to replace it

  connection {
    host     = self.ip
    user     = "root"
    password = self.password
  }

  provisioner "remote-exec" {
    inline = local.install_tailscale
  }
}

resource "gigahost_dns_record" "server2" {
  zone_id = data.gigahost_dns_zone.demo.id
  name    = "server2"
  type    = "A"
  value   = gigahost_server.server2.ip
  ttl     = 60
}

# For logging in by hand: server2 has no SSH key.
output "server2_password" {
  value     = gigahost_server.server2.password
  sensitive = true
}
