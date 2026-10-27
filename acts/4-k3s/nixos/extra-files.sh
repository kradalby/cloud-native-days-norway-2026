#!/bin/sh
# nixos-anywhere runs this in the new root before install. Keeps the k3s token out
# of the world-readable Nix store.
set -e
install -D -m 600 "$K3S_TOKEN_FILE" var/lib/k3s/token
