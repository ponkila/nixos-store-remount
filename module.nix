{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.services.storeRemount;
in
{
  options.services.storeRemount = with lib; {
    enable = lib.mkEnableOption "Nix store remount";

    where = mkOption {
      type = types.str;
      description = "Absolute path of device node, file or other resource.";
      example = "/dev/sdX";
    };

    options = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of options used to mount the file system.";
      example = [ "noatime" ];
    };

    type = mkOption {
      type = types.str;
      description = "File system type.";
      example = "ext4";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.store-remount = {
      enable = true;
      description = "Mount /nix/.rw-store and /tmp to disk";
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      # Prepare and mount backing device
      preStart = ''
        mkdir -p /nix/.rw-store
        ${pkgs.util-linux}/bin/mount -t ${cfg.type} ${cfg.where} /nix/.rw-store \
        ${
          if cfg.options != []
          then "-o ${lib.concatStringsSep "," cfg.options}"
          else ""
        }

        mkdir -p /nix/.rw-store/{work,store,tmp}
        chmod 1777 /nix/.rw-store/tmp
      '';

      # Mount overlay and bind /tmp
      script = ''
        ${pkgs.util-linux}/bin/mount -t overlay overlay -o lowerdir=/nix/.ro-store:/nix/store,upperdir=/nix/.rw-store/store,workdir=/nix/.rw-store/work /nix/store
        mkdir -p /tmp
        ${pkgs.util-linux}/bin/mount --bind /nix/.rw-store/tmp /tmp
      '';

      # Unmount all mounts
      preStop = ''
        ${pkgs.util-linux}/bin/umount -l /tmp || true
        ${pkgs.util-linux}/bin/umount -l /nix/store || true
        ${pkgs.util-linux}/bin/umount -l /nix/.rw-store || true
      '';

      wantedBy = [ "local-fs.target" ];
      before = [ "local-fs.target" ];
    };
  };
}

