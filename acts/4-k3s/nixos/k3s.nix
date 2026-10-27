# k3s over the tailnet: nodes talk on tailscale0, never on the public
# interface. k3s1 runs the control plane, the others join it.
{
  hostName,
  lib,
  pkgs,
  ...
}: let
  server = hostName == "k3s1";
in {
  services.k3s = {
    enable = true;
    role =
      if server
      then "server"
      else "agent";
    serverAddr = lib.mkIf (!server) "https://k3s1.demo.onpremise.no:6443";
    tokenFile = "/var/lib/k3s/token";
    extraFlags =
      ["--flannel-iface=tailscale0"]
      ++ lib.optionals server [
        "--tls-san=k3s1.demo.onpremise.no"
        "--disable=traefik"
        "--disable=servicelb"
      ];
  };

  # tailscale0 needs its address before k3s picks the node IP.
  systemd.services.k3s = {
    after = ["tailscaled-autoconnect.service"];
    wants = ["tailscaled-autoconnect.service"];
  };

  networking.firewall.trustedInterfaces = ["cni0" "flannel.1"];

  environment.systemPackages = [pkgs.kubernetes-helm];
  environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
}
