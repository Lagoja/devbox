{
  description = "Instant, easy, predictable dev environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    ,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        lastTag = "0.17.0";

        revision = if (self ? shortRev) then "${self.shortRev}" else "${self.dirtyShortRev or "dirty"}";

        # Add the commit to the version string for flake builds
        version = "${lastTag}";

        # Run `devbox run update-flake` to update the vendor-hash
        vendorHash = if builtins.pathExists ./vendor-hash then builtins.readFile ./vendor-hash else "";

        buildGoModule = pkgs.buildGo125Module;

      in
      {
        inherit self;
        packages.default = buildGoModule {
          pname = "devbox";
          inherit version vendorHash;

          src = ./.;

          subpackage = [ ./cmd/devbox ];

          ldflags = [
            "-s"
            "-w"
            "-X go.jetify.com/devbox/internal/build.Version=${version}"
            "-X go.jetify.com/devbox/internal/build.Commit=${revision}"
          ];

          # Don't generate test binaries (as we'd include them as a bin)
          excludedPackages = [ "testscripts" ];

          # Disable tests if they require network access or are integration tests
          doCheck = false;

          nativeBuildInputs = [ pkgs.installShellFiles ];

          postInstall = pkgs.lib.optionalString (pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform) ''
            installShellCompletion --cmd devbox \
              --bash <($out/bin/devbox completion bash) \
              --fish <($out/bin/devbox completion fish) \
              --zsh <($out/bin/devbox completion zsh)
          '';

          meta = with pkgs.lib; {
            description = "Instant, easy, and predictable development environments";
            homepage = "https://www.jetify.com/devbox";
            license = licenses.asl20;
            maintainers = with maintainers; [ lagoja ];
          };
        };
      }
    ) // {
      # lib is system-independent — consumers pass the system string themselves.
      lib = {
        # packagesFromLock :: (path | attrset) -> string -> [derivation]
        #
        # Reads a devbox.lock file and returns a list of Nix derivations for the
        # given system. Each package is resolved via its pinned nixpkgs rev and
        # attribute path, making this fully pure (no network calls beyond what
        # Nix's eval cache already handles).
        #
        # Example:
        #   devbox-lib.lib.packagesFromLock ./devbox.lock pkgs.system
        packagesFromLock = lockFileOrData: system:
          let
            nixlib = nixpkgs.lib;

            lockData =
              if builtins.isAttrs lockFileOrData
              then lockFileOrData
              else builtins.fromJSON (builtins.readFile lockFileOrData);

            # The nixpkgs stdenv/channel entry keys look like "github:NixOS/nixpkgs/..."
            # These are infrastructure entries, not user packages — exclude them.
            isNixpkgsEntry = name: builtins.match "github:NixOS/nixpkgs/.*" name != null;
            userPackages = nixlib.filterAttrs (name: _: !(isNixpkgsEntry name)) lockData.packages;

            # Resolve a single package entry to a derivation.
            # pkg.resolved is "github:NixOS/nixpkgs/<rev>#<attr_path>"
            resolvePackage = _name: pkg:
              let
                # Split on "#" → ["github:NixOS/nixpkgs/<rev>", ["#"], "<attr_path>"]
                parts = builtins.split "#" pkg.resolved;
                flakeRef = builtins.elemAt parts 0;
                attrPath = builtins.elemAt parts 2;

                # Extract the full 40-char commit SHA from the flake ref.
                # The ref may optionally have a "?lastModified=..." suffix.
                revMatch = builtins.match "github:NixOS/nixpkgs/([a-f0-9]{40}).*" flakeRef;
                rev = builtins.elemAt revMatch 0;

                # Fetch the pinned nixpkgs. Pure when rev is a full commit SHA.
                pinnedNixpkgs = builtins.fetchTree {
                  type = "github";
                  owner = "NixOS";
                  repo = "nixpkgs";
                  inherit rev;
                };

                pkgs = pinnedNixpkgs.legacyPackages.${system};
              in
                # attrByPath handles nested paths like "python312Packages.pip"
                nixlib.attrByPath (nixlib.splitString "." attrPath) null pkgs;
          in
            builtins.filter (p: p != null)
              (builtins.attrValues (builtins.mapAttrs resolvePackage userPackages));
      };
    };
}
