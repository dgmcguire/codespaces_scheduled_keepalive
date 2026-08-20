{
  description = "Wake and keep a GitHub Codespace alive during configured work hours";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
        };
    in
    {
      overlays.default = final: _prev: {
        codespaces-keepalive = final.callPackage ./nix/package.nix { };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        rec {
          codespaces-keepalive = pkgs.callPackage ./nix/package.nix { };
          default = codespaces-keepalive;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/codespaces-keepalive";
        };
      });

      homeManagerModules.default = import ./nix/home-manager-module.nix;
      homeManagerModules.codespaces-keepalive = self.homeManagerModules.default;

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          package = self.packages.${system}.default;
          tests = pkgs.runCommand "codespaces-keepalive-tests" {
            src = lib.cleanSource ./.;
            nativeBuildInputs = [
              pkgs.dash
              pkgs.coreutils
            ];
          } ''
            cp -a $src src
            cd src
            HOME=$TMPDIR dash tests/test_schedule.sh
            touch $out
          '';
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.gh
              pkgs.dash
              pkgs.shellcheck
            ];
          };
        }
      );
    };
}
