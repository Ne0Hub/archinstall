###https://www.lisenet.com/2013/luks-add-keys-backup-and-restore-volume-header
cryptsetup luksDump /dev/sda3
cryptsetup luksAddKey--key-slot 1 /dev/sda3 --key-file .keyfile
cryptsetup luksDump /dev/sda3
cryptsetup --test-passphrase luksOpen /dev/sda3 && echo correct
###https://gist.github.com/gutoandreollo/e12455886149a6c85a70

mkdir -p /mnt/btrfs-root
mount -o defaults,relatime,space_cache /dev/mapper/SLASH /mnt/btrfs-root
mkdir -p /mnt/btrfs-root/__active
mkdir -p /mnt/btrfs-root/__snapshot

cd /mnt/btrfs-root
btrfs subvolume create __active/rootvol
btrfs subvolume create __active/home
btrfs subvolume create __active/var
btrfs subvolume create __active/opt

mkdir -p /mnt/btrfs-active
mount -o defaults,nodev,relatime,space_cache,subvol=__active/rootvol /dev/mapper/SLASH /mnt/btrfs-active

mkdir -p /mnt/btrfs-active/{home,opt,var,var/lib,boot}
mount -o defaults,nosuid,nodev,relatime,subvol=__active/home /dev/mapper/SLASH /mnt/btrfs-active/home
mount -o defaults,nosuid,nodev,relatime,subvol=__active/opt /dev/mapper/SLASH /mnt/btrfs-active/opt
mount -o defaults,nosuid,nodev,noexec,relatime,subvol=__active/var /dev/mapper/SLASH /mnt/btrfs-active/var

mkdir -p /mnt/btrfs-active/var/lib
mount --bind /mnt/btrfs-root/__active/rootvol/var/lib /mnt/btrfs-active/var/lib

mount -o defaults,nosuid,nodev,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro /dev/sda1 /mnt/btrfs-active/boot

#pacstrap /mnt/btrfs-active base base-devel btrfs-progs

#genfstab -U -p /mnt/btrfs-active >> /mnt/btrfs-active/etc/fstab
#vi /mnt/btrfs-active/etc/fstab
