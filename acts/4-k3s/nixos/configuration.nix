# hostName and host (IPs, SSH keys) come from tofu, see k3s.tf.
{
  hostName,
  host,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ./k3s.nix
  ];

  networking.hostName = hostName;

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  users.users.root.openssh.authorizedKeys.keys = host.sshKeys;

  # Gigahost has no DHCP or router adverts: static addresses only.
  networking.useDHCP = false;
  networking.interfaces.ens18 = {
    ipv4.addresses = [
      {
        address = host.ipv4;
        prefixLength = 24;
      }
    ];
    ipv6.addresses = [
      {
        address = host.ipv6;
        prefixLength = 118;
      }
    ];
  };
  networking.defaultGateway = {
    address = host.ipv4Gateway;
    interface = "ens18";
  };
  networking.defaultGateway6 = {
    address = host.ipv6Gateway;
    interface = "ens18";
  };
  networking.nameservers = ["1.1.1.1" "1.0.0.1"];

  # The tailnet is the private network: everything on it gets in.
  networking.firewall.trustedInterfaces = ["tailscale0"];
  networking.firewall.checkReversePath = "loose";

  # Joins headscale once act 4 puts the key there (acts/4-k3s/k3s-join.tf).
  services.tailscale = {
    enable = true;
    authKeyFile = "/var/lib/tailscale/authkey";
    extraUpFlags = [
      "--login-server=https://vpn.demo.headscale.no"
      "--ssh"
      "--accept-routes"
      "--accept-dns"
    ];
  };

  # Without the key, a skip: a failed join would fail the prep install.
  systemd.services.tailscaled-autoconnect.unitConfig.ConditionPathExists = "/var/lib/tailscale/authkey";

  system.stateVersion = "25.05";
}
