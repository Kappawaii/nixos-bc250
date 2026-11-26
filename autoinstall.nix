# Unattended installer. WARNING: wipes the disk set in disko.nix as soon as it boots.
{ config, pkgs, lib, target, ... }:
let
  toplevel = target.config.system.build.toplevel;
  diskoScript = target.config.system.build.diskoScript;
in
{
  image.baseName = lib.mkForce "bc250-autoinstall";   # ISO file name, without .iso

  # SSH into the live installer to watch progress: ssh root@<its IP>, journalctl -fu bc250-autoinstall
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys =
    (import ./private.nix).sshKeys;

  systemd.services.bc250-autoinstall = {
    description = "Wipe the NVMe and install NixOS for bc250";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    path = [
      config.system.build.nixos-install
      pkgs.nix
      pkgs.coreutils
      pkgs.util-linux
      pkgs.gawk
      pkgs.gnugrep
    ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    script = ''
      set -euxo pipefail
      # Find the target: the one real disk that is NOT the stick we booted from
      lsblk -d -o NAME,SIZE,TRAN,RM,MODEL
      src=$(readlink -f "$(findmnt -no SOURCE /iso)")
      bootdisk=$(lsblk -ndo PKNAME "$src")
      [ -n "$bootdisk" ] || bootdisk=$(basename "$src")
      echo "Booted from /dev/$bootdisk, leaving it alone"
      disks=$(lsblk -dn -o NAME,TYPE | awk -v b="$bootdisk" '$2=="disk" && $1!=b && $1!~/^(loop|zram|sr)/ {print $1}')
      if [ "$(echo "$disks" | grep -c .)" -ne 1 ]; then
        echo "Expected exactly one target disk, found: '$disks'. Aborting, nothing touched."
        exit 1
      fi
      ln -sf "/dev/$disks" /dev/bc250-target
      echo "Installing to /dev/$disks"
      # Partition, format and mount at /mnt (layout from disko.nix)
      ${diskoScript}
      # The full system closure is already on the USB stick, so this works offline
      nixos-install --root /mnt --system ${toplevel} --no-root-passwd --no-channel-copy
      sync
      # Power off rather than reboot, so the board can't boot the stick again and reinstall
      poweroff
    '';
  };
}
