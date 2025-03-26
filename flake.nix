{
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    devenv.url = "github:cachix/devenv";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, ... }@inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = inputs.nixpkgs.lib.systems.flakeExposed;
      imports = [ inputs.devenv.flakeModule ];

      perSystem =
        { pkgs
        , self'
        , outputs
        , ...
        }:
        {
          devenv.shells.default = {
            pre-commit.hooks = {
              nixpkgs-fmt.enable = true;
            };
            containers = pkgs.lib.mkForce { };
          };

          # Tests -> 'nix flake check --impure -L'
          checks.storeRemount = pkgs.testers.runNixOSTest {
            name = "storeRemount‑service‑boots";
            nodes.machine = { ... }: {
              imports = [ self.nixosModules.storeRemount ];
              services.storeRemount = {
                enable = true;
                where = "/dev/vda";
                type = "ext4";
                options = [ "noatime" ];
              };
              environment.systemPackages = [ pkgs.hello ];
              services.getty.autologinUser = "root";
            };

            node.pkgsReadOnly = false;
            node.specialArgs = { inherit inputs outputs; };

            testScript = ''
              def check():
                  machine.succeed("mountpoint /nix/.rw-store")
                  machine.succeed("mountpoint /tmp")
                  machine.succeed("hello")

              machine.start()
              machine.wait_for_unit("store-remount.service")
              check()

              # Ensure 'nixos-rebuild' compability
              machine.succeed("systemctl restart store-remount.service")
              machine.wait_for_unit("store-remount.service")
              check()
            '';
          };

          # Interactive mode -> `nix run .#test` then `machine.shell_interact()`
          packages.test = self'.checks.storeRemount.driverInteractive;
        };

      flake = {
        nixosModules = {
          storeRemount = import ./module.nix;
          default = self.nixosModules.storeRemount;
        };
      };
    };
}
