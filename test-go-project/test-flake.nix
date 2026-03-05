# Example: consuming packagesFromLock in a stereOS mixtape flake.
#
# This shows how a mixtape author would wire up devbox.lock so that
# the exact same packages used in `devbox shell` are baked into the
# stereOS VM image — no Devbox required at runtime.
#
# Usage:
#   stereos.agent.extraPackages = devbox-lib.lib.packagesFromLock ./devbox.lock system;
{
  description = "My stereOS mixtape";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    stereos.url = "github:papercomputeco/stereOS";

    # Point at the Devbox repo to get the Nix library.
    # In a real mixtape this would be: "github:jetify-com/devbox"
    devbox-lib.url = "path:../";
  };

  outputs = { self, nixpkgs, stereos, devbox-lib }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # Resolve packages from devbox.lock at eval time.
      # `devbox update` → commit devbox.lock → VM rebuilds with updated packages.
      stereosConfigurations.default = stereos.lib.mkMixtape {
        inherit system;
        modules = [{
          stereos.agent = {
            # Same packages as `devbox shell`, baked into the VM image.
            extraPackages = devbox-lib.lib.packagesFromLock ./devbox.lock system;
          };
        }];
      };
    };
}
