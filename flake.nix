{
  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
  # Not eachDefaultSystem: nixpkgs 26.11 dropped x86_64-darwin and throws on eval.
    flake-utils.lib.eachSystem ["x86_64-linux" "aarch64-linux" "aarch64-darwin"]
    (system: let
      pkgs = nixpkgs.legacyPackages.${system};

      # Not on the OpenTofu registry: built the nixpkgs way, into the registry
      # layout that .envrc points a filesystem mirror at. The rev is the tested one.
      terraform-provider-gigahost = pkgs.terraform-providers.mkProvider {
        owner = "kradalby";
        repo = "terraform-provider-gigahost";
        rev = "ab503ea51f66ce96b39af90ec3920f154a503e74";
        version = "0.0.1";
        hash = "sha256-SudFeUQZquiTQE78mhGnQkP6PVX17vBj36Oyr2WJPSY=";
        vendorHash = "sha256-qrjuPdvdKZBgo2MRJyOFWG+xYwfU/5ZNEL7Pb8yPaOs=";
        mkProviderGoModule = pkgs.buildGo127Module;
        provider-source-address = "registry.opentofu.org/kradalby/gigahost";
      };
    in {
      formatter = pkgs.alejandra;

      packages = {inherit terraform-provider-gigahost;};

      # nixos-anywhere (acts/4-k3s) builds with the host's nix, not one from here.
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          opentofu
          jq
          alejandra
        ];
        GIGAHOST_PROVIDER_MIRROR = "${terraform-provider-gigahost}/libexec/terraform-providers";
      };
    });
}
