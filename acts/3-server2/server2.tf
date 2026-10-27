resource "tailscale_tailnet_key" "server2" {
  tags          = ["tag:server"]
  preauthorized = true
  expiry        = 3600
  description   = "server2"
}

# The VM is in server2-vm.tf, up since before the talk.
resource "terraform_data" "server2_join" {
  connection {
    host     = gigahost_server.server2.ip
    user     = "root"
    password = gigahost_server.server2.password
  }

  # A file, not inline: a sensitive value in remote-exec hides all its output.
  provisioner "file" {
    content     = tailscale_tailnet_key.server2.key
    destination = "/root/tskey"
  }

  provisioner "remote-exec" {
    inline = [
      "tailscale up --login-server=https://vpn.demo.headscale.no --auth-key=file:/root/tskey --ssh --accept-routes --accept-dns",
    ]
  }
}
