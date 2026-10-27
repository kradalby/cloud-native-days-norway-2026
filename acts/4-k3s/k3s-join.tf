resource "tailscale_tailnet_key" "k3s" {
  for_each = gigahost_server.k3s

  tags          = ["tag:k3s"]
  preauthorized = true
  expiry        = 3600
  # The server ID makes a new server get a new key; the old one is used up.
  description = "${each.key} ${each.value.id}"
}

# The nodes run NixOS with Tailscale since before the talk, but no key.
resource "terraform_data" "k3s_join" {
  for_each = gigahost_server.k3s

  connection {
    host = each.value.ip
    user = "root"
  }

  # A file, not inline: a sensitive value in remote-exec hides all its output.
  provisioner "file" {
    content     = tailscale_tailnet_key.k3s[each.key].key
    destination = "/var/lib/tailscale/authkey"
  }

  # The unit is Type=notify: the restart returns once the node is on the tailnet.
  provisioner "remote-exec" {
    inline = [
      "chmod 600 /var/lib/tailscale/authkey",
      "systemctl restart tailscaled-autoconnect",
    ]
  }
}
