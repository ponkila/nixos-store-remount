{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = { self, ... }@inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = inputs.nixpkgs.lib.systems.flakeExposed;
      imports = [
        inputs.git-hooks.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        { pkgs
        , config
        , self'
        , outputs
        , ...
        }:
        {
          # Nix code formatter -> 'nix fmt'
          treefmt.config = {
            projectRootFile = "flake.nix";
            flakeFormatter = true;
            flakeCheck = true;
            programs = {
              nixpkgs-fmt.enable = true;
              deadnix.enable = true;
              statix.enable = true;
            };
          };

          # Pre-commit hooks
          pre-commit.check.enable = false;
          pre-commit.settings.hooks.treefmt = {
            enable = true;
            package = config.treefmt.build.wrapper;
          };

          # Development shell -> 'nix develop' or 'direnv allow'
          devShells.default = pkgs.mkShell {
            packages = [ pkgs.pre-commit pkgs.gh ];
            shellHook = config.pre-commit.installationScript;
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

              # Test service: verifies PrivateTmp works with store-remount's /tmp bind mount
              systemd.services.private-tmp-test = {
                description = "Test that PrivateTmp works after store-remount";
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  PrivateTmp = true;
                  ExecStart = pkgs.writeShellScript "private-tmp-test" ''
                    echo "ok" > /run/private-tmp-test-ok
                  '';
                };
                wantedBy = [ "multi-user.target" ];
              };
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

              # Verify store-remount is ordered before local-fs.target
              # so that /tmp is available for services using mount namespaces (PrivateTmp, LoadCredential)
              before = machine.succeed("systemctl show store-remount.service -p Before --value").strip().split()
              assert "local-fs.target" in before, \
                  f"store-remount must be ordered before local-fs.target, got Before={' '.join(before)}"

              # Verify no ordering cycles were detected during boot
              machine.fail("journalctl -b --no-pager | grep -q 'ordering cycle'")

              # Verify a service with PrivateTmp=true works (requires /tmp to be mounted)
              machine.wait_for_unit("private-tmp-test.service")
              machine.succeed("cat /run/private-tmp-test-ok")

              # Ensure 'nixos-rebuild' compatibility
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
