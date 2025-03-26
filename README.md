
# NixOS Store Remount

A NixOS module that remounts the Nix store as a writable **overlay filesystem** and binds `/tmp` to it — handy for ephemeral systems.

## Getting Started

Add this repository as a Nix flake input, then enable the module in your NixOS configuration:

```nix
{
  inputs = {
    store-remount.url = "github:ponkila/nixos-store-remount";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, ... }@inputs: {
    nixosConfigurations = {
      yourhostname = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          inputs.store-remount.nixosModules.storeRemount
          {
            # Module configuration
            services.storeRemount = { ... };
          }
        ];
      };
    };
  };
}
```

## Module Configuration

### Options

- **`enable`** - Enable remounting of the Nix store.
- **`where`** - Absolute path of device node, file or other resource.
- **`type`** - Filesystem type.
- **`options`** - List of options used to mount the file system.

These are comparable to the *Where=*, *Type=*, and *Options=* fields of [`systemd.mount`](https://www.freedesktop.org/software/systemd/man/latest/systemd.mount.html#Options).

## Examples

### Dedicated partition

```nix
{
  services.storeRemount = {
    enable  = true;
    where   = "/dev/disk/by-uuid/xxxxxxxx";
    type    = "ext4";
    options = [ "noatime" ];
  };
}
```

### Bind under an existing mount

```nix
{
  services.storeRemount = {
    enable  = true;
    where   = "/mnt/drive/store";
    type    = "none";
    options = [ "bind" "noatime" ];
  };
}
```

