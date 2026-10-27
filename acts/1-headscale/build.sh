#!/bin/sh
# Builds headscale into ./headscale.deb, the way releases are built.
# Run it again to pull the branch and rebuild.
set -e
cd "$(dirname "$0")"
repo=https://github.com/kradalby/headscale
# Frozen at the tested talk build. kradalby/set-dns is the moving tip.
branch=kradalby/set-dns-cndn2026
# Treeless, not shallow: goreleaser needs the tags to version the package.
[ -d src ] || git clone -q --filter=tree:0 "$repo" src
cd src
# Checkout, not pull: the branch gets rebased, and the build dirties the tree.
git fetch -q origin "$branch"
git checkout -q --force --detach FETCH_HEAD
git clean -q -fdx
git log -1 --format='building %h %s'
# Not plain describe: main carries non-release tags (backup/...).
export GORELEASER_CURRENT_TAG=$(git describe --tags --abbrev=0 --match "v[0-9]*")
# headscale's own dev shell, as in its release workflow: right Go, goreleaser.
nix develop --command goreleaser release --snapshot --clean --skip=ko
cp dist/headscale_*_linux_amd64.deb ../headscale.deb
