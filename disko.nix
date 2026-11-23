# Disk layout for the target drive (picked automatically by the autoinstaller).
# /dev/bc250-target is a symlink the autoinstaller creates to the only disk that
# is not the installer stick (USB, SATA or NVMe), so the stick is never wiped.
# Partitions are mounted by partition label afterwards, so the symlink isn't needed after install.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/bc250-target";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
